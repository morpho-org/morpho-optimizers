// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./aave/IAaveIncentivesController.sol";

interface IRewardsManager {
    function aaveIncentivesController() external view returns (IAaveIncentivesController);

    function setAaveIncentivesController(address) external;

    function getUserIndex(address, address) external returns (uint256);

    function accrueUserUnclaimedRewards(address[] calldata, address) external returns (uint256);

    function getUserUnclaimedRewards(address[] calldata, address) external view returns (uint256);

    function claimRewards(address[] calldata, address) external returns (uint256);

    function updateUserAssetAndAccruedRewards(
        address,
        address,
        uint256,
        uint256
    ) external;
}
