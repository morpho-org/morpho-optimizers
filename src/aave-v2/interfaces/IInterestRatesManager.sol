// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;

interface IInterestRatesManager {
    function updateIndexes(address _marketAddress) external;
}
