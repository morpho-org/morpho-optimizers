// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IRewardsManager {
    function updateUserAssetAndAccruedRewards(
        address,
        address,
        uint256,
        uint256
    ) external;

    function accrueRewardsForAssetsBeforeClaiming(
        address[] calldata,
        uint256,
        address
    ) external returns (uint256);
}
