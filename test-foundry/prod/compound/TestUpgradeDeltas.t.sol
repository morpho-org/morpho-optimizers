// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestDeltas.t.sol";

contract TestUpgradeDeltas is TestDeltas {
    function setUp() public override {
        super.setUp();

        _upgrade();
    }
}
