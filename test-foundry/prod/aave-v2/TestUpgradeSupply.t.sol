// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestSupply.t.sol";

contract TestUpgradeSupply is TestSupply {
    function setUp() public override {
        super.setUp();

        _upgrade();
    }
}
