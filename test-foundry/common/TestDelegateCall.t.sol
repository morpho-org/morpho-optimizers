// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "forge-std/stdlib.sol";

import "@contracts/common/libraries/DelegateCall.sol";

contract TestDelegateCall is DSTest {
    using DelegateCall for address;

    Vm public hevm = Vm(HEVM_ADDRESS);

    function testShouldNotDelegateCallToNotContractAddress() public {
        hevm.expectRevert(DelegateCall.TargetIsNotContract.selector);
        address(0).functionDelegateCall("0x");
    }
}
