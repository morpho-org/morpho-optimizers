// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./TestDeltas.t.sol";

contract TestUpgradeDeltas is TestDeltas {
    function setUp() public override {
        super.setUp();

        _upgrade();
    }
}
