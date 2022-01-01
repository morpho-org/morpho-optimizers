// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IPositionsManager {
    struct SupplyBalance {
        uint256 inP2P;
        uint256 onPool;
    }

    struct BorrowBalance {
        uint256 inP2P;
        uint256 onPool;
    }

    function createMarket(address) external returns (uint256[] memory);

    function updateMaxIterations(uint16) external;

    function updatePositionsUpdator(address) external;

    function setThreshold(address, uint256) external;

    function setCapValue(address, uint256) external;

    function supplyBalanceInOf(address, address) external returns (SupplyBalance memory);

    function borrowBalanceInOf(address, address) external returns (BorrowBalance memory);
}
