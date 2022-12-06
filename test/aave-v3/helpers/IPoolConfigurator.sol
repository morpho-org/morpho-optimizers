// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

interface IPoolConfigurator {
    function setReserveFreeze(address asset, bool freeze) external;
}
