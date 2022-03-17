// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IPositionsManagerForCompound {
    struct Balance {
        uint256 inP2P;
        uint256 onPool;
    }

    struct Delta {
        uint256 supplyP2PDelta;
        uint256 borrowP2PDelta;
        uint256 supplyP2PAmount;
        uint256 borrowP2PAmount;
    }

    function createMarket(address) external returns (uint256[] memory);

    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable);

    function setNMAX(uint16) external;

    function setTreasuryVault(address) external;

    function setRewardsManager(address _rewardsManagerAddress) external;

    function borrowBalanceInOf(address, address) external returns (Balance memory);

    function supplyBalanceInOf(address, address) external returns (Balance memory);

    function deltas(address) external view returns (Delta memory);
}
