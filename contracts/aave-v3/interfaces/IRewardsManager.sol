// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";

interface IRewardsManager {
    function rewardsController() external view returns (IRewardsController);

    function setRewardsController(address) external;

    function getUserAccruedRewards(
        address[] calldata _assets,
        address _user,
        address _reward
    ) external view returns (uint256 totalAccrued);

    function getAllUserRewards(address[] calldata _assets, address _user)
        external
        view
        returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts);

    function getUserAssetIndex(
        address _user,
        address _asset,
        address _reward
    ) external view returns (uint256);

    function getUserRewards(
        address[] calldata _assets,
        address _user,
        address _reward
    ) external view returns (uint256);

    function claimRewards(
        address[] calldata,
        address,
        address[] calldata
    ) external returns (address[] memory rewardsList, uint256[] memory claimedAmount);

    function updateUserAssetAndAccruedRewards(
        address,
        address,
        uint256,
        uint256
    ) external;
}
