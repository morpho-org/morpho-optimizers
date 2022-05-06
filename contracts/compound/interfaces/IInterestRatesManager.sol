// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IInterestRatesManager {
    function updateP2PIndexes(address _marketAddress) external;

    function getUpdatedP2PIndexes(address _poolTokenAddress) external returns (uint256, uint256);
}
