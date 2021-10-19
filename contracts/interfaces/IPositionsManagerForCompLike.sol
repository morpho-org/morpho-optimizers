// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IPositionsManagerForCompLike {
    function createMarket(address _marketAddress) external returns (uint256[] memory);

    function setComptroller(address _proxyComptrollerAddress) external;

    function setThreshold(address, uint256) external;

    function marketsManagerForCompLike() external returns (address);

    function supplyBalanceInOf(address, address) external returns (uint256, uint256);

    function supply(address, uint256) external;

    function withdraw(address, uint256) external;
}
