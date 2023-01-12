// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./interfaces/IRewardsManager.sol";
import "./interfaces/IMorpho.sol";

import "@morpho-dao/morpho-utils/math/CompoundMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title RewardsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract is used to manage the COMP rewards from the Compound protocol.
contract RewardsManager is IRewardsManager, Initializable {
    using CompoundMath for uint256;
    using SafeCast for uint256;

    /// STORAGE ///

    mapping(address => uint256) public userUnclaimedCompRewards; // The unclaimed rewards of the user.
    mapping(address => mapping(address => uint256)) public compSupplierIndex; // The supply index of the user for a specific cToken. cToken -> user -> index.
    mapping(address => mapping(address => uint256)) public compBorrowerIndex; // The borrow index of the user for a specific cToken. cToken -> user -> index.
    mapping(address => IComptroller.CompMarketState) public localCompSupplyState; // The local supply state for a specific cToken.
    mapping(address => IComptroller.CompMarketState) public localCompBorrowState; // The local borrow state for a specific cToken.

    IMorpho public morpho;
    IComptroller public comptroller;

    /// ERRORS ///

    /// @notice Thrown when only Morpho can call the function.
    error OnlyMorpho();

    /// @notice Thrown when an invalid cToken address is passed to claim rewards.
    error InvalidCToken();

    /// MODIFIERS ///

    /// @notice Thrown when an other address than Morpho triggers the function.
    modifier onlyMorpho() {
        if (msg.sender != address(morpho)) revert OnlyMorpho();
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}

    /// UPGRADE ///

    /// @notice Initializes the RewardsManager contract.
    /// @param _morpho The address of Morpho's main contract's proxy.
    function initialize(address _morpho) external initializer {
        morpho = IMorpho(_morpho);
        comptroller = IComptroller(morpho.comptroller());
    }

    /// EXTERNAL ///

    /// @notice Returns the local COMP supply state.
    /// @param _poolToken The cToken address.
    /// @return The local COMP supply state.
    function getLocalCompSupplyState(address _poolToken)
        external
        view
        returns (IComptroller.CompMarketState memory)
    {
        return localCompSupplyState[_poolToken];
    }

    /// @notice Returns the local COMP borrow state.
    /// @param _poolToken The cToken address.
    /// @return The local COMP borrow state.
    function getLocalCompBorrowState(address _poolToken)
        external
        view
        returns (IComptroller.CompMarketState memory)
    {
        return localCompBorrowState[_poolToken];
    }

    /// @notice Accrues unclaimed COMP rewards for the given cToken addresses and returns the total COMP unclaimed rewards.
    /// @dev This function is called by the `morpho` to accrue COMP rewards and reset them to 0.
    /// @dev The transfer of tokens is done in the `morpho`.
    /// @param _poolTokens The cToken addresses for which to claim rewards.
    /// @param _user The address of the user.
    function claimRewards(address[] calldata _poolTokens, address _user)
        external
        onlyMorpho
        returns (uint256 totalUnclaimedRewards)
    {
        totalUnclaimedRewards = _accrueUserUnclaimedRewards(_poolTokens, _user);
        if (totalUnclaimedRewards > 0) userUnclaimedCompRewards[_user] = 0;
    }

    /// @notice Updates the unclaimed COMP rewards of the user.
    /// @param _user The address of the user.
    /// @param _poolToken The cToken address.
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserSupplyUnclaimedRewards(
        address _user,
        address _poolToken,
        uint256 _userBalance
    ) external onlyMorpho {
        _updateSupplyIndex(_poolToken);
        userUnclaimedCompRewards[_user] += _accrueSupplierComp(_user, _poolToken, _userBalance);
    }

    /// @notice Updates the unclaimed COMP rewards of the user.
    /// @param _user The address of the user.
    /// @param _poolToken The cToken address.
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserBorrowUnclaimedRewards(
        address _user,
        address _poolToken,
        uint256 _userBalance
    ) external onlyMorpho {
        _updateBorrowIndex(_poolToken);
        userUnclaimedCompRewards[_user] += _accrueBorrowerComp(_user, _poolToken, _userBalance);
    }

    /// INTERNAL ///

    /// @notice Accrues unclaimed COMP rewards for the cToken addresses and returns the total unclaimed COMP rewards.
    /// @param _poolTokens The cToken addresses for which to accrue rewards.
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function _accrueUserUnclaimedRewards(address[] calldata _poolTokens, address _user)
        internal
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedCompRewards[_user];

        for (uint256 i; i < _poolTokens.length; ) {
            address poolToken = _poolTokens[i];

            (bool isListed, , ) = comptroller.markets(poolToken);
            if (!isListed) revert InvalidCToken();

            _updateSupplyIndex(poolToken);
            unclaimedRewards += _accrueSupplierComp(
                _user,
                poolToken,
                morpho.supplyBalanceInOf(poolToken, _user).onPool
            );

            _updateBorrowIndex(poolToken);
            unclaimedRewards += _accrueBorrowerComp(
                _user,
                poolToken,
                morpho.borrowBalanceInOf(poolToken, _user).onPool
            );

            unchecked {
                ++i;
            }
        }

        userUnclaimedCompRewards[_user] = unclaimedRewards;
    }

    /// @notice Updates supplier index and returns the accrued COMP rewards of the supplier since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _poolToken The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function _accrueSupplierComp(
        address _supplier,
        address _poolToken,
        uint256 _balance
    ) internal returns (uint256) {
        uint256 supplyIndex = localCompSupplyState[_poolToken].index;
        uint256 supplierIndex = compSupplierIndex[_poolToken][_supplier];
        compSupplierIndex[_poolToken][_supplier] = supplyIndex;

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    /// @notice Updates borrower index and returns the accrued COMP rewards of the borrower since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _poolToken The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function _accrueBorrowerComp(
        address _borrower,
        address _poolToken,
        uint256 _balance
    ) internal returns (uint256) {
        uint256 borrowIndex = localCompBorrowState[_poolToken].index;
        uint256 borrowerIndex = compBorrowerIndex[_poolToken][_borrower];
        compBorrowerIndex[_poolToken][_borrower] = borrowIndex;

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }

    /// @notice Updates the COMP supply index.
    /// @param _poolToken The cToken address.
    function _updateSupplyIndex(address _poolToken) internal {
        IComptroller.CompMarketState storage localSupplyState = localCompSupplyState[_poolToken];

        if (localSupplyState.block == block.number) return;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _poolToken
            );

            uint256 deltaBlocks = block.number - supplyState.block;
            uint256 supplySpeed = comptroller.compSupplySpeeds(_poolToken);

            uint224 newCompSupplyIndex;
            if (deltaBlocks > 0 && supplySpeed > 0) {
                uint256 supplyTokens = ICToken(_poolToken).totalSupply();
                uint256 compAccrued = deltaBlocks * supplySpeed;
                uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;

                newCompSupplyIndex = uint224(supplyState.index + ratio);
            } else newCompSupplyIndex = supplyState.index;

            localCompSupplyState[_poolToken] = IComptroller.CompMarketState({
                index: newCompSupplyIndex,
                block: block.number.toUint32()
            });
        }
    }

    /// @notice Updates the COMP borrow index.
    /// @param _poolToken The cToken address.
    function _updateBorrowIndex(address _poolToken) internal {
        IComptroller.CompMarketState storage localBorrowState = localCompBorrowState[_poolToken];

        if (localBorrowState.block == block.number) return;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _poolToken
            );

            uint256 deltaBlocks = block.number - borrowState.block;
            uint256 borrowSpeed = comptroller.compBorrowSpeeds(_poolToken);

            uint224 newCompBorrowIndex;
            if (deltaBlocks > 0 && borrowSpeed > 0) {
                ICToken cToken = ICToken(_poolToken);

                uint256 borrowAmount = cToken.totalBorrows().div(cToken.borrowIndex());
                uint256 compAccrued = deltaBlocks * borrowSpeed;
                uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;

                newCompBorrowIndex = uint224(borrowState.index + ratio);
            } else newCompBorrowIndex = borrowState.index;

            localCompBorrowState[_poolToken] = IComptroller.CompMarketState({
                index: newCompBorrowIndex,
                block: block.number.toUint32()
            });
        }
    }
}
