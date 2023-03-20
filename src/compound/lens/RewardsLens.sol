// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./MarketsLens.sol";

/// @title RewardsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer serving as proxy to lighten the bytecode weight of the Lens.
abstract contract RewardsLens is MarketsLens {
    /// EXTERNAL ///

    /// @notice Returns the unclaimed COMP rewards for the given cToken addresses.
    /// @param _poolTokens The cToken addresses for which to compute the rewards.
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _poolTokens, address _user)
        external
        view
        returns (uint256)
    {
        return lensExtension.getUserUnclaimedRewards(_poolTokens, _user);
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
    ) external view returns (uint256) {
        return lensExtension.getAccruedSupplierComp(_supplier, _poolToken, _balance);
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
        return lensExtension.getAccruedSupplierComp(_supplier, _poolToken);
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
    ) external view returns (uint256) {
        return lensExtension.getAccruedBorrowerComp(_borrower, _poolToken, _balance);
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
        return lensExtension.getAccruedBorrowerComp(_borrower, _poolToken);
    }

    /// @notice Returns the updated COMP supply index.
    /// @param _poolToken The cToken address.
    /// @return The updated COMP supply index.
    function getCurrentCompSupplyIndex(address _poolToken) external view returns (uint256) {
        return lensExtension.getCurrentCompSupplyIndex(_poolToken);
    }

    /// @notice Returns the updated COMP borrow index.
    /// @param _poolToken The cToken address.
    /// @return The updated COMP borrow index.
    function getCurrentCompBorrowIndex(address _poolToken) external view returns (uint256) {
        return lensExtension.getCurrentCompBorrowIndex(_poolToken);
    }
}
