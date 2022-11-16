// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestSupply.t.sol";

contract TestUpgradeSupply is TestSupply {
    function testUpgradeShouldSupplyAllMarketsP2PAndOnPool(uint96 _amount) public {
        _upgrade();

        testShouldSupplyAllMarketsP2PAndOnPool(_amount);
    }

    function testUpgradeShouldNotSupplyZeroAmount() public {
        _upgrade();

        testShouldNotSupplyZeroAmount();
    }

    function testUpgradeShouldNotSupplyOnBehalfAddressZero(uint96 _amount) public {
        _upgrade();

        testShouldNotSupplyOnBehalfAddressZero(_amount);
    }
}
