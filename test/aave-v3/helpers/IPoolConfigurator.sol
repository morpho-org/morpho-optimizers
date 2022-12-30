// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IPoolConfigurator {
    function setReserveFreeze(address asset, bool freeze) external;
}
