// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./RatesLens.sol";

/// @title RewardsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol rewards distribution.
abstract contract RewardsLens is RatesLens {
    /// EXTERNAL ///

    /// @notice Get the unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _assets The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return The user unclaimed rewards.
    function getUserUnclaimedRewards(address[] calldata _assets, address _user)
        external
        view
        returns (uint256)
    {
        return rewardsManager.getUserUnclaimedRewards(_assets, _user);
    }

    /// @notice Returns the index of the `_user` for a given `_asset`.
    /// @param _asset The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return The index of the user.
    function getUserIndex(address _asset, address _user) external view returns (uint256) {
        return rewardsManager.getUserIndex(_asset, _user);
    }
}
