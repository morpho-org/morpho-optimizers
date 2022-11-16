// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestWithdraw.t.sol";

contract TestUpgradeWithdraw is TestWithdraw {
    function testUpgradeShouldWithdrawAllMarketsP2PAndOnPool(uint96 _amount) public {
        _upgrade();

        testShouldWithdrawAllMarketsP2PAndOnPool(_amount);
    }

    function testUpgradeShouldNotWithdrawZeroAmount() public {
        _upgrade();

        testShouldNotWithdrawZeroAmount();
    }

    function testUpgradeShouldNotWithdrawFromUnenteredMarket(uint96 _amount) public {
        _upgrade();

        testShouldNotWithdrawFromUnenteredMarket(_amount);
    }
}
