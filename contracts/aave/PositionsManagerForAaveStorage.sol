// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "./interfaces/IMatchingEngineForAave.sol";
import "./interfaces/IRewardsManager.sol";

import "../common/libraries/DoubleLinkedList.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PositionsManagerForAaveStorage is ReentrancyGuard {
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

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint16 public NMAX = 1000;
    uint8 public constant NO_REFERRAL_CODE = 0;
    uint8 public constant VARIABLE_INTEREST_MODE = 2;
    uint256 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // 50 % in basis points.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.
    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on Aave.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on Aave.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of a user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of a user.
    mapping(address => mapping(address => bool)) public userMembership; // Whether the user is in the market or not.
    mapping(address => address[]) public enteredMarkets; // The markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IMarketsManagerForAave public marketsManagerForAave;
    IAaveIncentivesController public aaveIncentivesController;
    IRewardsManager public rewardsManager;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public lendingPool;
    IProtocolDataProvider public dataProvider;
    IMatchingEngineForAave public matchingEngineForAave;
    address public treasuryVault;
}
