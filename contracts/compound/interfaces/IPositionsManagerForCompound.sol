// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IPositionsManagerForCompound {
    function createMarket(address _marketAddress) external returns (uint256[] memory);

    function setMaxNumberOfUsersInTree(uint16) external;

    function setThreshold(address, uint256) external;
}
