// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestBorrow.t.sol";

contract TestUpgradeBorrow is TestBorrow {
    function _beforeEach() internal override {
        _upgrade();
    }
}
