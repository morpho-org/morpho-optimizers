// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../libraries/CompoundMath.sol";

import "./UsersLens.sol";

/// @title RewardsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol rewards distribution.
abstract contract RewardsLens is UsersLens {
    using CompoundMath for uint256;

    /// ERRORS ///

    /// @notice Thrown when an invalid cToken address is passed to compute accrued rewards.
    error InvalidCToken();

    /// EXTERNAL ///

    /// @notice Returns the unclaimed COMP rewards for the given cToken addresses.
    /// @param _poolTokenAddresses The cToken addresses for which to compute the rewards.
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _poolTokenAddresses, address _user)
        external
        view
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = rewardsManager.userUnclaimedCompRewards(_user);

        for (uint256 i; i < _poolTokenAddresses.length; ) {
            address cTokenAddress = _poolTokenAddresses[i];

            (bool isListed, , ) = comptroller.markets(cTokenAddress);
            if (!isListed) revert InvalidCToken();

            unclaimedRewards += getAccruedSupplierComp(
                _user,
                cTokenAddress,
                morpho.supplyBalanceInOf(cTokenAddress, _user).onPool
            );
            unclaimedRewards += getAccruedBorrowerComp(
                _user,
                cTokenAddress,
                morpho.borrowBalanceInOf(cTokenAddress, _user).onPool
            );

            unchecked {
                ++i;
            }
        }
    }

    /// PUBLIC ///

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _poolTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedSupplierComp(
        address _supplier,
        address _poolTokenAddress,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 supplyIndex = getUpdatedCompSupplyIndex(_poolTokenAddress);
        uint256 supplierIndex = rewardsManager.compSupplierIndex(_poolTokenAddress, _supplier);

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _poolTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedBorrowerComp(
        address _borrower,
        address _poolTokenAddress,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 borrowIndex = getUpdatedCompBorrowIndex(_poolTokenAddress);
        uint256 borrowerIndex = rewardsManager.compBorrowerIndex(_poolTokenAddress, _borrower);

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }

    /// @notice Returns the updated COMP supply index.
    /// @param _poolTokenAddress The cToken address.
    /// @return The updated COMP supply index.
    function getUpdatedCompSupplyIndex(address _poolTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localSupplyState = rewardsManager
        .getLocalCompSupplyState(_poolTokenAddress);

        if (localSupplyState.block == block.number) return localSupplyState.index;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _poolTokenAddress
            );

            uint256 deltaBlocks = block.number - supplyState.block;
            uint256 supplySpeed = comptroller.compSupplySpeeds(_poolTokenAddress);

            if (deltaBlocks > 0 && supplySpeed > 0) {
                uint256 supplyTokens = ICToken(_poolTokenAddress).totalSupply();
                uint256 compAccrued = deltaBlocks * supplySpeed;
                uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;

                return supplyState.index + ratio;
            }

            return supplyState.index;
        }
    }

    /// @notice Returns the updated COMP borrow index.
    /// @param _poolTokenAddress The cToken address.
    /// @return The updated COMP borrow index.
    function getUpdatedCompBorrowIndex(address _poolTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localBorrowState = rewardsManager
        .getLocalCompBorrowState(_poolTokenAddress);

        if (localBorrowState.block == block.number) return localBorrowState.index;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _poolTokenAddress
            );
            uint256 deltaBlocks = block.number - borrowState.block;
            uint256 borrowSpeed = comptroller.compBorrowSpeeds(_poolTokenAddress);

            if (deltaBlocks > 0 && borrowSpeed > 0) {
                ICToken cToken = ICToken(_poolTokenAddress);

                uint256 borrowAmount = cToken.totalBorrows().div(cToken.borrowIndex());
                uint256 compAccrued = deltaBlocks * borrowSpeed;
                uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;

                return borrowState.index + ratio;
            }

            return borrowState.index;
        }
    }
}
