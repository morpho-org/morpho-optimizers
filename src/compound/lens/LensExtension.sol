// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "../interfaces/IRewardsManager.sol";
import "../interfaces/IMorpho.sol";
import "./interfaces/ILensExtension.sol";

import "@morpho-dao/morpho-utils/math/CompoundMath.sol";

/// @title LensExtension.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract is an extension of the Lens. It should be deployed before the Lens, as the Lens depends on its address to extends its functionalities.
contract LensExtension is ILensExtension {
    using CompoundMath for uint256;

    /// STORAGE ///

    IMorpho public immutable morpho;
    IComptroller internal immutable comptroller;
    IRewardsManager internal immutable rewardsManager;

    /// ERRORS ///

    /// @notice Thrown when an invalid cToken address is passed to claim rewards.
    error InvalidCToken();

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @param _morpho The address of the main Morpho contract.
    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        comptroller = IComptroller(morpho.comptroller());
        rewardsManager = IRewardsManager(morpho.rewardsManager());
    }

    /// EXTERNAL ///

    /// @notice Returns the unclaimed COMP rewards for the given cToken addresses.
    /// @param _poolTokens The cToken addresses for which to compute the rewards.
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _poolTokens, address _user)
        external
        view
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = rewardsManager.userUnclaimedCompRewards(_user);

        for (uint256 i; i < _poolTokens.length; ) {
            address poolToken = _poolTokens[i];

            (bool isListed, , ) = comptroller.markets(poolToken);
            if (!isListed) revert InvalidCToken();

            unclaimedRewards +=
                getAccruedSupplierComp(_user, poolToken) +
                getAccruedBorrowerComp(_user, poolToken);

            unchecked {
                ++i;
            }
        }
    }

    /// PUBLIC ///

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _poolToken The cToken address.
    /// @return The accrued COMP rewards.
    function getAccruedSupplierComp(address _supplier, address _poolToken)
        public
        view
        returns (uint256)
    {
        return
            getAccruedSupplierComp(
                _supplier,
                _poolToken,
                morpho.supplyBalanceInOf(_poolToken, _supplier).onPool
            );
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _poolToken The cToken address.
    /// @return The accrued COMP rewards.
    function getAccruedBorrowerComp(address _borrower, address _poolToken)
        public
        view
        returns (uint256)
    {
        return
            getAccruedBorrowerComp(
                _borrower,
                _poolToken,
                morpho.borrowBalanceInOf(_poolToken, _borrower).onPool
            );
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _poolToken The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedSupplierComp(
        address _supplier,
        address _poolToken,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 supplierIndex = rewardsManager.compSupplierIndex(_poolToken, _supplier);

        if (supplierIndex == 0) return 0;
        return (_balance * (getCurrentCompSupplyIndex(_poolToken) - supplierIndex)) / 1e36;
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _poolToken The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedBorrowerComp(
        address _borrower,
        address _poolToken,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 borrowerIndex = rewardsManager.compBorrowerIndex(_poolToken, _borrower);

        if (borrowerIndex == 0) return 0;
        return (_balance * (getCurrentCompBorrowIndex(_poolToken) - borrowerIndex)) / 1e36;
    }

    /// @notice Returns the updated COMP supply index.
    /// @param _poolToken The cToken address.
    /// @return The updated COMP supply index.
    function getCurrentCompSupplyIndex(address _poolToken) public view returns (uint256) {
        IComptroller.CompMarketState memory localSupplyState = rewardsManager
        .getLocalCompSupplyState(_poolToken);

        if (localSupplyState.block == block.number) return localSupplyState.index;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _poolToken
            );

            uint256 deltaBlocks = block.number - supplyState.block;
            uint256 supplySpeed = comptroller.compSupplySpeeds(_poolToken);

            if (deltaBlocks > 0 && supplySpeed > 0) {
                uint256 supplyTokens = ICToken(_poolToken).totalSupply();
                uint256 ratio = supplyTokens > 0
                    ? (deltaBlocks * supplySpeed * 1e36) / supplyTokens
                    : 0;

                return supplyState.index + ratio;
            }

            return supplyState.index;
        }
    }

    /// @notice Returns the updated COMP borrow index.
    /// @param _poolToken The cToken address.
    /// @return The updated COMP borrow index.
    function getCurrentCompBorrowIndex(address _poolToken) public view returns (uint256) {
        IComptroller.CompMarketState memory localBorrowState = rewardsManager
        .getLocalCompBorrowState(_poolToken);

        if (localBorrowState.block == block.number) return localBorrowState.index;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _poolToken
            );
            uint256 deltaBlocks = block.number - borrowState.block;
            uint256 borrowSpeed = comptroller.compBorrowSpeeds(_poolToken);

            if (deltaBlocks > 0 && borrowSpeed > 0) {
                uint256 borrowAmount = ICToken(_poolToken).totalBorrows().div(
                    ICToken(_poolToken).borrowIndex()
                );
                uint256 ratio = borrowAmount > 0
                    ? (deltaBlocks * borrowSpeed * 1e36) / borrowAmount
                    : 0;

                return borrowState.index + ratio;
            }

            return borrowState.index;
        }
    }
}
