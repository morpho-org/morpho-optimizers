// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestSupply.t.sol";

contract TestUpgradeSupply is TestSupply {
    function _beforeEach() internal override {
        _upgrade();
    }
}
