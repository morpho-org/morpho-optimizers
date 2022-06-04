// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IInterestRatesManager {
    function updateIndexes(address _poolTokenAddress) external;
}
