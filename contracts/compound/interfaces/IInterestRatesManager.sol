// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IInterestRatesManager {
    function updateP2PIndexes(address _marketAddress) external;
}
