// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IPositionsManagerForCompLike {
    function createMarket(address _marketAddress) external returns (uint256[] memory);

    function setComptroller(address _proxyComptrollerAddress) external;

    function setThreshold(address, uint256) external;
}
