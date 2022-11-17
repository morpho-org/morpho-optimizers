// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestWithdraw.t.sol";

contract TestUpgradeWithdraw is TestWithdraw {
    function _beforeEach() internal override {
        _upgrade();
    }
}
