// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IRewardsManager {
    function claimRewards(
        address[] calldata,
        uint256,
        address
    ) external returns (uint256);

    function getUserUnclaimedRewards(address[] calldata, address) external returns (uint256);

    function updateUserAssetAndAccruedRewards(
        address,
        address,
        uint256,
        uint256
    ) external;
}
