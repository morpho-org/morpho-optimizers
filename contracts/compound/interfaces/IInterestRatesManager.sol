// SPDX-License-Identifier: GNU AGPLv3

pragma solidity >=0.5.0;

interface IInterestRatesManager {
    function updateP2PIndexes(address _marketAddress) external;
}
