// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IPositionsManagerForAave {
    struct Balance {
        uint256 inP2P;
        uint256 onPool;
    }

    function createMarket(address) external returns (uint256[] memory);

    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable);

    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external;

    function setThreshold(address _poolTokenAddress, uint256 _newThreshold) external;

    function setCapValue(address _poolTokenAddress, uint256 _newCapValue) external;

    function setTreasuryVault(address) external;

    function setRewardsManager(address _rewardsManagerAddress) external;

    function borrowBalanceInOf(address, address) external returns (Balance memory);

    function supplyBalanceInOf(address, address) external returns (Balance memory);
}
