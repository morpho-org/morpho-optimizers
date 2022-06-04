// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface IInterestRatesManager {
    function updateIndexes(address _marketAddress) external;
}
