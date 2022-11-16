// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestBorrow.t.sol";

contract TestUpgradeBorrow is TestBorrow {
    function testUpgradeShouldBorrowAmountP2PAndFromPool(uint96 _amount) public {
        _upgrade();

        testShouldBorrowAmountP2PAndFromPool(_amount);
    }

    function testUpgradeShouldNotBorrowZeroAmount() public {
        _upgrade();

        testShouldNotBorrowZeroAmount();
    }

    function testUpgradeShouldNotBorrowWithoutEnoughCollateral(uint96 _amount) public {
        _upgrade();

        testShouldNotBorrowWithoutEnoughCollateral(_amount);
    }
}
