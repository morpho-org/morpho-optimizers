// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;

import "./aave/IAaveIncentivesController.sol";

interface IRewardsManager {
    function initialize(address _morpho) external;

    function getUserIndex(address, address) external returns (uint256);

    function getUserUnclaimedRewards(address[] calldata, address) external view returns (uint256);

    function claimRewards(
        IAaveIncentivesController _aaveIncentivesController,
        address[] calldata,
        address
    ) external returns (uint256);

    function updateUserAssetAndAccruedRewards(
        IAaveIncentivesController _aaveIncentivesController,
        address _user,
        address _asset,
        uint256 _userBalance,
        uint256 _totalBalance
    ) external;
}
