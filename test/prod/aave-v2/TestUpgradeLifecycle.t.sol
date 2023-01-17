// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./TestLifecycle.t.sol";

contract TestUpgradeLifecycle is TestLifecycle {
    function setUp() public override {
        super.setUp();

        _upgrade();
    }
}
