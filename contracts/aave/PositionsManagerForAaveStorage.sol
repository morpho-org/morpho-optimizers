// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "./interfaces/IMatchingEngineForAave.sol";
import "./interfaces/IRewardsManager.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract PositionsManagerForAaveStorage is ReentrancyGuard, Pausable {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// Structs ///

    struct SupplyBalance {
        uint256 inP2P; // In supplier's p2pUnit, a unit that grows in value, to keep track of the interests earned when users are in P2P.
        uint256 onPool; // In aToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's p2pUnit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when users are in Aave. Multiply by current borrowIndex to get the underlying amount.
    }

    /// Storage ///

    uint8 public NMAX = 20;
    uint8 public constant NO_REFERRAL_CODE = 0;
    uint8 public constant VARIABLE_INTEREST_MODE = 2;
    uint16 public constant MAX_BASIS_POINTS = 10000; // 100% in basis points.
    uint16 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // 50% in basis points.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.
    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on Aave.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on Aave.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of a user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of a user.
    mapping(address => uint256) public supplyP2PDelta; // Difference between the stored P2P supply amount and the real P2P supply amount (in scaled balance).
    mapping(address => uint256) public borrowP2PDelta; // Difference between the stored P2P borrow amount and the real P2P borrow amount (in adUnit).
    mapping(address => uint256) public supplyP2PAmount; // Sum of all stored P2P supply (in P2P unit).
    mapping(address => uint256) public borrowP2PAmount; // Sum of all stored P2P borrow (in P2P unit).
    mapping(address => mapping(address => bool)) public userMembership; // Whether the user is in the market or not.
    mapping(address => address[]) public enteredMarkets; // The markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IAaveIncentivesController public aaveIncentivesController;
    ILendingPoolAddressesProvider public addressesProvider;
    IProtocolDataProvider public dataProvider;
    ILendingPool public lendingPool;
    IMarketsManagerForAave public marketsManager;
    IMatchingEngineForAave public matchingEngine;
    IRewardsManager public rewardsManager;
    address public treasuryVault;

    /// Internal ///

    /// @notice Supplies undelrying tokens to Aave.
    /// @param _poolTokenAddress The address of the market
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyERC20ToPool(
        address _poolTokenAddress,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
        marketsManager.updateSPYs(_poolTokenAddress);
    }

    /// @notice Withdraws underlying tokens from Aave.
    /// @param _poolTokenAddress The address of the market.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    function _withdrawERC20FromPool(
        address _poolTokenAddress,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
        marketsManager.updateSPYs(_poolTokenAddress);
    }

    /// @notice Borrows underlying tokens from Aave.
    /// @param _poolTokenAddress The address of the market.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowERC20FromPool(
        address _poolTokenAddress,
        IERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        lendingPool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
        marketsManager.updateSPYs(_poolTokenAddress);
    }

    /// @notice Repays underlying tokens to Aave.
    /// @param _poolTokenAddress The address of the market.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    /// @param _normalizedVariableDebt The normalized variable debt on Aave.
    function _repayERC20ToPool(
        address _poolTokenAddress,
        IERC20 _underlyingToken,
        uint256 _amount,
        uint256 _normalizedVariableDebt
    ) internal {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        (, , address variableDebtToken) = dataProvider.getReserveTokensAddresses(
            address(_underlyingToken)
        );
        // Do not repay more than the contract's debt on Aave
        _amount = Math.min(
            _amount,
            IVariableDebtToken(variableDebtToken).scaledBalanceOf(address(this)).mulWadByRay(
                _normalizedVariableDebt
            )
        );
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
        marketsManager.updateSPYs(_poolTokenAddress);
    }
}
