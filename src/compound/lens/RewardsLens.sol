// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./MarketsLens.sol";

/// @title RewardsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol rewards distribution.
abstract contract RewardsLens is MarketsLens {
    using CompoundMath for uint256;

    /// ERRORS ///

    /// @notice Thrown when an invalid cToken address is passed to compute accrued rewards.
    error InvalidPoolToken();

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
            address cTokenAddress = _poolTokens[i];

            (bool isListed, , ) = comptroller.markets(cTokenAddress);
            if (!isListed) revert InvalidPoolToken();

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
    /// @param _poolToken The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedSupplierComp(
        address _supplier,
        address _poolToken,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 supplyIndex = getCurrentCompSupplyIndex(_poolToken);
        uint256 supplierIndex = rewardsManager.compSupplierIndex(_poolToken, _supplier);

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _poolToken The cToken address.
    /// @return The accrued COMP rewards.
    function getAccruedSupplierComp(address _supplier, address _poolToken)
        external
        view
        returns (uint256)
    {
        uint256 supplyIndex = getCurrentCompSupplyIndex(_poolToken);
        uint256 supplierIndex = rewardsManager.compSupplierIndex(_poolToken, _supplier);

        if (supplierIndex == 0) return 0;
        return
            (morpho.supplyBalanceInOf(_poolToken, _supplier).onPool *
                (supplyIndex - supplierIndex)) / 1e36;
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
        uint256 borrowIndex = getCurrentCompBorrowIndex(_poolToken);
        uint256 borrowerIndex = rewardsManager.compBorrowerIndex(_poolToken, _borrower);

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _poolToken The cToken address.
    /// @return The accrued COMP rewards.
    function getAccruedBorrowerComp(address _borrower, address _poolToken)
        external
        view
        returns (uint256)
    {
        uint256 borrowIndex = getCurrentCompBorrowIndex(_poolToken);
        uint256 borrowerIndex = rewardsManager.compBorrowerIndex(_poolToken, _borrower);

        if (borrowerIndex == 0) return 0;
        return
            (morpho.borrowBalanceInOf(_poolToken, _borrower).onPool *
                (borrowIndex - borrowerIndex)) / 1e36;
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
                uint256 compAccrued = deltaBlocks * supplySpeed;
                uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;

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
                ICToken cToken = ICToken(_poolToken);

                uint256 borrowAmount = cToken.totalBorrows().div(cToken.borrowIndex());
                uint256 compAccrued = deltaBlocks * borrowSpeed;
                uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;

                return borrowState.index + ratio;
            }

            return borrowState.index;
        }
    }
}
