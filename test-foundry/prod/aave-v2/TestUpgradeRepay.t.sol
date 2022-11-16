// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestRepay.t.sol";

contract TestUpgradeRepay is TestRepay {
    function testUpgradeShouldRepayAmountP2PAndFromPool(uint96 _amount) public {
        _upgrade();

        testShouldRepayAmountP2PAndFromPool(_amount);
    }

    function testUpgradeShouldNotRepayZeroAmount() public {
        _upgrade();

        testShouldNotRepayZeroAmount();
    }
}
