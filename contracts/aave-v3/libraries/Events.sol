// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

library Events {
    /// @notice Emitted when a user claims rewards.
    /// @param user The address of the claimer.
    /// @param reward The reward token address.
    /// @param amountClaimed The amount of reward token claimed.
    /// @param traded Whether or not the pool tokens are traded against Morpho tokens.
    event RewardsClaimed(
        address indexed user,
        address indexed reward,
        uint256 amountClaimed,
        bool indexed traded
    );
}
