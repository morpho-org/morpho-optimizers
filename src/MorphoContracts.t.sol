// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./MorphoContracts.sol";

contract MorphoContractsTest is DSTest {
    MorphoContracts contracts;

    function setUp() public {
        contracts = new MorphoContracts();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
