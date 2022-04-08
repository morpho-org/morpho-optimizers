// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IRewardsManagerForCompound {
    function accrueUserUnclaimedRewards(address[] calldata, address) external returns (uint256);

    function claimRewards(
        address[] calldata,
        uint256,
        address
    ) external returns (uint256);

    function updateUserAssetAndAccruedRewards(
        address,
        address,
        uint256,
        uint256
    ) external;
}
