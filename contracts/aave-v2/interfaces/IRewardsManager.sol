// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./aave/IAaveIncentivesController.sol";

interface IRewardsManager {
    function initialize(address _morpho) external;

    function aaveIncentivesController() external view returns (IAaveIncentivesController);

    function setAaveIncentivesController(address) external;

    function getUserIndex(address, address) external view returns (uint256);

    function getUserUnclaimedRewards(address[] calldata, address) external view returns (uint256);

    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalBalance
    ) external;

    function claimRewards(address[] calldata, address) external returns (uint256);
}
