// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/Types.sol";

interface IMorpho {
    struct Balance {
        uint256 inP2P;
        uint256 onPool;
    }

    function createMarket(address) external returns (uint256[] memory);

    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable);

    function setNMAX(uint16) external;

    function setTreasuryVault(address) external;

    function setRewardsManager(address _rewardsManagerAddress) external;

    function borrowBalanceInOf(address, address) external view returns (Balance memory);

    function supplyBalanceInOf(address, address) external view returns (Balance memory);

    function noP2P(address _poolTokenAddress) external view returns (bool);

    function deltas(address) external view returns (Types.Delta memory);

    function cEth() external view returns (address);

    function comptroller() external view returns (address);

    function marketStatuses(address)
        external
        view
        returns (
            bool,
            bool,
            bool
        );

    function p2pSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function p2pBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedp2pSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedp2pBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function updateP2PIndexes(address _marketAddress) external;

    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        returns (uint256, uint256);
}
