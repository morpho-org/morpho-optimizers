// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface ILendingPoolConfigurator {
    function freezeReserve(address asset) external;
}
