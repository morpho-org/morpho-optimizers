// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "forge-std/stdlib.sol";

import "@contracts/common/libraries/Heap.sol";

contract TestHeap is DSTest {
    using BasicHeap for BasicHeap.Heap;

    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public NDS = 50;
    address[] public accounts;
    address public ADDR_ZERO = address(0);

    BasicHeap.Heap internal heap;

    function setUp() public {
        accounts = new address[](NDS);
        accounts[0] = address(this);
        for (uint256 i = 1; i < NDS; i++) {
            accounts[i] = address(uint160(accounts[i - 1]) + 1);
        }
    }

    function testInsertOneSingleAccount() public {
        heap.update(accounts[0], 0, 1);

        assertEq(heap.length(), 1);
        assertEq(heap.getValueOf(accounts[0]), 1);
        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[0]);
        assertEq(heap.getPrev(accounts[0]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[0]), ADDR_ZERO);
    }

    function testShouldNotInsertAccountWithZeroValue() public {
        heap.update(accounts[0], 0, 0);
        assertEq(heap.length(), 0);
    }

    function testShouldNotInsertZeroAddress() public {
        hevm.expectRevert(abi.encodeWithSignature("AddressIsZero()"));
        heap.update(address(0), 0, 10);
    }

    function testShouldInsertSeveralTimesTheSameAccount() public {
        heap.update(accounts[0], 0, 1);
        heap.update(accounts[0], 1, 2);
        assertEq(heap.getValueOf(accounts[0]), 2);
    }

    function testShouldHaveTheRightOrder() public {
        heap.update(accounts[0], 0, 20);
        heap.update(accounts[1], 0, 40);
        assertEq(heap.getHead(), accounts[1]);
        assertEq(heap.getTail(), accounts[0]);
    }

    function testShouldRemoveOneSingleAccount() public {
        heap.update(accounts[0], 0, 1);
        heap.update(accounts[0], 1, 0);

        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
        assertEq(heap.getValueOf(accounts[0]), 0);
        assertEq(heap.getPrev(accounts[0]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[0]), ADDR_ZERO);
    }

    function testShouldInsertTwoAccounts() public {
        heap.update(accounts[0], 0, 2);
        heap.update(accounts[1], 0, 1);

        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[1]);
        assertEq(heap.getValueOf(accounts[0]), 2);
        assertEq(heap.getValueOf(accounts[1]), 1);
        assertEq(heap.getPrev(accounts[0]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[0]), accounts[1]);
        assertEq(heap.getPrev(accounts[1]), accounts[0]);
        assertEq(heap.getNext(accounts[1]), ADDR_ZERO);
    }

    function testShouldInsertThreeAccounts() public {
        heap.update(accounts[0], 0, 3);
        heap.update(accounts[1], 0, 2);
        heap.update(accounts[2], 0, 1);

        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[2]);
        assertEq(heap.getValueOf(accounts[0]), 3);
        assertEq(heap.getValueOf(accounts[1]), 2);
        assertEq(heap.getValueOf(accounts[2]), 1);
        assertEq(heap.getPrev(accounts[0]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[0]), accounts[1]);
        assertEq(heap.getPrev(accounts[1]), accounts[0]);
        assertEq(heap.getNext(accounts[1]), accounts[2]);
        assertEq(heap.getPrev(accounts[2]), accounts[1]);
        assertEq(heap.getNext(accounts[2]), ADDR_ZERO);
    }

    function testShouldRemoveOneAccountOverTwo() public {
        heap.update(accounts[0], 0, 2);
        heap.update(accounts[1], 0, 1);
        heap.update(accounts[0], 2, 0);

        assertEq(heap.getHead(), accounts[1]);
        assertEq(heap.getTail(), accounts[1]);
        assertEq(heap.getValueOf(accounts[0]), 0);
        assertEq(heap.getValueOf(accounts[1]), 1);
        assertEq(heap.getPrev(accounts[1]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[1]), ADDR_ZERO);
    }

    function testShouldRemoveBothAccounts() public {
        heap.update(accounts[0], 0, 2);
        heap.update(accounts[1], 0, 1);
        heap.update(accounts[0], 2, 0);
        heap.update(accounts[1], 1, 0);

        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
    }

    function testShouldInsertThreeAccountsAndRemoveThem() public {
        heap.update(accounts[0], 0, 3);
        heap.update(accounts[1], 0, 2);
        heap.update(accounts[2], 0, 1);

        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[2]);

        // Remove account 0.
        heap.update(accounts[0], 3, 0);
        assertEq(heap.getHead(), accounts[1]);
        assertEq(heap.getTail(), accounts[2]);
        assertEq(heap.getPrev(accounts[1]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[1]), accounts[2]);

        assertEq(heap.getPrev(accounts[2]), accounts[1]);
        assertEq(heap.getNext(accounts[2]), ADDR_ZERO);

        // Remove account 1.
        heap.update(accounts[1], 2, 0);
        assertEq(heap.getHead(), accounts[2]);
        assertEq(heap.getTail(), accounts[2]);
        assertEq(heap.getPrev(accounts[2]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[2]), ADDR_ZERO);

        // Remove account 2.
        heap.update(accounts[2], 1, 0);
        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
    }

    function testShouldInsertAccountsAllSorted() public {
        for (uint256 i = 0; i < accounts.length; i++) {
            heap.update(accounts[i], 0, NDS - i);
        }

        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[accounts.length - 1]);

        address nextAccount = accounts[0];
        for (uint256 i = 0; i < accounts.length - 1; i++) {
            nextAccount = heap.getNext(nextAccount);
            assertEq(nextAccount, accounts[i + 1]);
        }

        address prevAccount = accounts[accounts.length - 1];
        for (uint256 i = 0; i < accounts.length - 1; i++) {
            prevAccount = heap.getPrev(prevAccount);
            assertEq(prevAccount, accounts[accounts.length - i - 2]);
        }
    }

    function testShouldRemoveAllSortedAccount() public {
        for (uint256 i = 0; i < accounts.length; i++) {
            heap.update(accounts[i], 0, NDS - i);
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            heap.update(accounts[i], NDS - i, 0);
        }

        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
    }

    function testShouldInsertAccountSortedAtTheBeginningUntilNDS() public {
        uint256 value = 50;

        // Add first 10 accounts with decreasing value.
        for (uint256 i = 0; i < 10; i++) {
            heap.update(accounts[i], 0, value - i);
        }

        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[9]);

        address nextAccount = accounts[0];
        for (uint256 i = 0; i < 9; i++) {
            nextAccount = heap.getNext(nextAccount);
            assertEq(nextAccount, accounts[i + 1]);
        }

        address prevAccount = accounts[9];
        for (uint256 i = 0; i < 9; i++) {
            prevAccount = heap.getPrev(prevAccount);
            assertEq(prevAccount, accounts[10 - i - 2]);
        }

        // Add last 10 accounts at the same value.
        for (uint256 i = NDS - 10; i < NDS; i++) {
            heap.update(accounts[i], 0, 10);
        }

        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[accounts.length - 1]);

        nextAccount = accounts[0];
        for (uint256 i = 0; i < 9; i++) {
            nextAccount = heap.getNext(nextAccount);
            assertEq(nextAccount, accounts[i + 1]);
        }

        prevAccount = accounts[9];
        for (uint256 i = 0; i < 9; i++) {
            prevAccount = heap.getPrev(prevAccount);
            assertEq(prevAccount, accounts[10 - i - 2]);
        }
    }
}
