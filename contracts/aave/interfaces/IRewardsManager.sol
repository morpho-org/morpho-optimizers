// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IRewardsManager {
    function userUnclaimedRewards(address) external view returns (uint256);

    function DATA_PROVIDER_ID() external view returns (bytes32);

    function claimRewards(
        address[] calldata _assets,
        uint256 _amount,
        address _user
    ) external returns (uint256 amountToClaim);

    function updateUserAssetAndAccruedRewards(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) external;

    function getUserIndex(address _asset, address _user) external returns (uint256);

    function getUserUnclaimedRewards(address[] calldata _assets, address _user)
        external
        returns (uint256);
}
