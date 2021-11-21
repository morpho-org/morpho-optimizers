// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IPositionsManagerForAave {
    function createMarket(address _marketAddress) external returns (uint256[] memory);

    function setMaxNumberOfUsersInTree(uint16) external;

    function setThreshold(address, uint256) external;
}
