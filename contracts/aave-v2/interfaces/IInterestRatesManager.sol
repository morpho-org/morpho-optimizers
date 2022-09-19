// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface IInterestRatesManager {
    function STETH() external view returns (address);

    function ST_ETH_REBASE_INDEX() external view returns (uint256);

    function updateIndexes(address _marketAddress) external;
}
