// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "forge-std/stdlib.sol";
import "forge-std/console.sol";

import "@contracts/common/libraries/Heap.sol";

contract TestHeap is DSTest {
    using BasicHeap for BasicHeap.Heap;

    Vm public hevm = Vm(HEVM_ADDRESS);

    address[] public accounts;
    uint256 public NB_ACCOUNTS = 50;
    uint256 public MAX_SORTED_USERS = 50;
    address public ADDR_ZERO = address(0);

    BasicHeap.Heap internal heap;

    function update(
        address _id,
        uint256 _formerValue,
        uint256 _newValue
    ) public {
        heap.update(_id, _formerValue, _newValue, MAX_SORTED_USERS);
    }

    function setUp() public {
        accounts = new address[](NB_ACCOUNTS);
        accounts[0] = address(this);
        for (uint256 i = 1; i < NB_ACCOUNTS; i++) {
            accounts[i] = address(uint160(accounts[i - 1]) + 1);
        }
    }

    function testInsertOneSingleAccount() public {
        update(accounts[0], 0, 1);

        assertEq(heap.length(), 1);
        assertEq(heap.getValueOf(accounts[0]), 1);
        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[0]);
        assertEq(heap.getPrev(accounts[0]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[0]), ADDR_ZERO);
    }

    function testShouldNotInsertAccountWithZeroValue() public {
        update(accounts[0], 0, 0);
        assertEq(heap.length(), 0);
    }

    function testShouldNotInsertZeroAddress() public {
        hevm.expectRevert(abi.encodeWithSignature("AddressIsZero()"));
        update(address(0), 0, 10);
    }

    function testShouldInsertSeveralTimesTheSameAccount() public {
        update(accounts[0], 0, 1);
        update(accounts[0], 1, 2);
        assertEq(heap.getValueOf(accounts[0]), 2);
    }

    function testShouldHaveTheRightOrder() public {
        update(accounts[0], 0, 20);
        update(accounts[1], 0, 40);
        assertEq(heap.getHead(), accounts[1]);
        assertEq(heap.getTail(), accounts[0]);
    }

    function testShouldRemoveOneSingleAccount() public {
        update(accounts[0], 0, 1);
        update(accounts[0], 1, 0);

        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
        assertEq(heap.getValueOf(accounts[0]), 0);
        assertEq(heap.getPrev(accounts[0]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[0]), ADDR_ZERO);
    }

    function testShouldInsertTwoAccounts() public {
        update(accounts[0], 0, 2);
        update(accounts[1], 0, 1);

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
        update(accounts[0], 0, 3);
        update(accounts[1], 0, 2);
        update(accounts[2], 0, 1);

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
        update(accounts[0], 0, 2);
        update(accounts[1], 0, 1);
        update(accounts[0], 2, 0);

        assertEq(heap.getHead(), accounts[1]);
        assertEq(heap.getTail(), accounts[1]);
        assertEq(heap.getValueOf(accounts[0]), 0);
        assertEq(heap.getValueOf(accounts[1]), 1);
        assertEq(heap.getPrev(accounts[1]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[1]), ADDR_ZERO);
    }

    function testShouldRemoveBothAccounts() public {
        update(accounts[0], 0, 2);
        update(accounts[1], 0, 1);
        update(accounts[0], 2, 0);
        update(accounts[1], 1, 0);

        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
    }

    function testShouldInsertThreeAccountsAndRemoveThem() public {
        update(accounts[0], 0, 3);
        update(accounts[1], 0, 2);
        update(accounts[2], 0, 1);

        assertEq(heap.getHead(), accounts[0]);
        assertEq(heap.getTail(), accounts[2]);

        // Remove account 0.
        update(accounts[0], 3, 0);
        assertEq(heap.getHead(), accounts[1]);
        assertEq(heap.getTail(), accounts[2]);
        assertEq(heap.getPrev(accounts[1]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[1]), accounts[2]);

        assertEq(heap.getPrev(accounts[2]), accounts[1]);
        assertEq(heap.getNext(accounts[2]), ADDR_ZERO);

        // Remove account 1.
        update(accounts[1], 2, 0);
        assertEq(heap.getHead(), accounts[2]);
        assertEq(heap.getTail(), accounts[2]);
        assertEq(heap.getPrev(accounts[2]), ADDR_ZERO);
        assertEq(heap.getNext(accounts[2]), ADDR_ZERO);

        // Remove account 2.
        update(accounts[2], 1, 0);
        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
    }

    function testShouldInsertAccountsAllSorted() public {
        for (uint256 i = 0; i < accounts.length; i++) {
            update(accounts[i], 0, NB_ACCOUNTS - i);
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
            update(accounts[i], 0, NB_ACCOUNTS - i);
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            update(accounts[i], NB_ACCOUNTS - i, 0);
        }

        assertEq(heap.getHead(), ADDR_ZERO);
        assertEq(heap.getTail(), ADDR_ZERO);
    }

    function testShouldInsertAccountSortedAtTheBeginningUntilNDS() public {
        uint256 value = 50;

        // Add first 10 accounts with decreasing value.
        for (uint256 i = 0; i < 10; i++) {
            update(accounts[i], 0, value - i);
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
        for (uint256 i = NB_ACCOUNTS - 10; i < NB_ACCOUNTS; i++) {
            update(accounts[i], 0, 10);
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

    function testComputeSizeSmall() public {
        update(accounts[0], 0, 10);
        update(accounts[1], 0, 20);
        update(accounts[2], 0, 30);
        update(accounts[3], 0, 40);
        update(accounts[4], 0, 50);
        update(accounts[5], 0, 60);

        MAX_SORTED_USERS = 2;

        update(accounts[5], 60, 25);
        assertEq(heap.size, 1);
    }

    function testComputeSizeBig() public {
        MAX_SORTED_USERS = 30;

        for (uint256 i = 0; i < NB_ACCOUNTS; i++) {
            update(accounts[i], 0, i + 1);
        }

        assertEq(heap.size, 20);
    }

    function testShiftUpLeft() public {
        update(accounts[0], 0, 4);
        update(accounts[1], 0, 3);
        update(accounts[2], 0, 2);

        assertEq(heap.accounts[0].value, 4);
        assertEq(heap.accounts[1].value, 3);
        assertEq(heap.accounts[2].value, 2);

        update(accounts[2], 2, 10);

        assertEq(heap.accounts[0].value, 10);
        assertEq(heap.accounts[1].value, 3);
        assertEq(heap.accounts[2].value, 4);
    }

    function testShiftUpRight() public {
        update(accounts[0], 0, 4);
        update(accounts[1], 0, 3);
        update(accounts[2], 0, 2);

        update(accounts[1], 3, 10);

        assertEq(heap.accounts[0].value, 10);
        assertEq(heap.accounts[1].value, 4);
        assertEq(heap.accounts[2].value, 2);
    }

    function testShiftUpBig() public {
        update(accounts[0], 0, 20);
        update(accounts[1], 0, 15);
        update(accounts[2], 0, 18);
        update(accounts[3], 0, 11);
        update(accounts[4], 0, 12);
        update(accounts[5], 0, 17);
        update(accounts[6], 0, 16);

        assertEq(heap.accounts[0].value, 20);
        assertEq(heap.accounts[1].value, 15);
        assertEq(heap.accounts[2].value, 18);
        assertEq(heap.accounts[3].value, 11);
        assertEq(heap.accounts[4].value, 12);
        assertEq(heap.accounts[5].value, 17);
        assertEq(heap.accounts[6].value, 16);

        update(accounts[4], 12, 30);

        assertEq(heap.accounts[4].value, 15);
        assertEq(heap.accounts[1].value, 20);
        assertEq(heap.accounts[0].value, 30);
    }

    function testShiftDownRight() public {
        update(accounts[0], 0, 4);
        update(accounts[1], 0, 3);
        update(accounts[2], 0, 2);

        update(accounts[0], 4, 1);

        assertEq(heap.accounts[0].value, 3);
        assertEq(heap.accounts[1].value, 1);
        assertEq(heap.accounts[2].value, 2);
    }

    function testShiftDownLeft() public {
        update(accounts[0], 0, 4);
        update(accounts[1], 0, 2);
        update(accounts[2], 0, 3);

        update(accounts[0], 4, 1);

        assertEq(heap.accounts[0].value, 3);
        assertEq(heap.accounts[1].value, 2);
        assertEq(heap.accounts[2].value, 1);
    }

    function testShiftDownBig() public {
        update(accounts[0], 0, 20);
        update(accounts[1], 0, 15);
        update(accounts[2], 0, 18);
        update(accounts[3], 0, 11);
        update(accounts[4], 0, 12);
        update(accounts[5], 0, 17);
        update(accounts[6], 0, 16);

        update(accounts[0], 20, 10);

        assertEq(heap.accounts[0].value, 18);
        assertEq(heap.accounts[2].value, 17);
        assertEq(heap.accounts[5].value, 10);
    }

    function testSouldInsertSorted() public {
        update(accounts[0], 0, 1);
        update(accounts[1], 0, 2);
        update(accounts[2], 0, 3);
        update(accounts[3], 0, 4);
        update(accounts[4], 0, 5);
        update(accounts[5], 0, 6);
        update(accounts[6], 0, 7);

        assertEq(heap.accounts[0].value, 7);
        assertEq(heap.accounts[1].value, 4);
        assertEq(heap.accounts[2].value, 6);
        assertEq(heap.accounts[3].value, 1);
        assertEq(heap.accounts[4].value, 3);
        assertEq(heap.accounts[5].value, 2);
        assertEq(heap.accounts[6].value, 5);
    }

    function testInsertLast() public {
        for (uint256 i; i < 10; i++) update(accounts[i], 0, NB_ACCOUNTS - i);

        for (uint256 i = 10; i < 15; i++) update(accounts[i], 0, i - 9);

        for (uint256 i = 10; i < 15; i++) assertLe(heap.accounts[i].value, 10);
    }

    function testInsertWrap() public {
        MAX_SORTED_USERS = 20;
        for (uint256 i = 0; i < 20; i++) update(accounts[i], 0, NB_ACCOUNTS - i);

        update(accounts[20], 0, 1);

        assertEq(heap.accounts[10].value, 1);
    }

    function testDecreaseIndexChanges() public {
        MAX_SORTED_USERS = 4;
        for (uint256 i = 0; i < 16; i++) update(accounts[i], 0, 20 - i);

        uint256 index5Before = heap.indexes[accounts[5]];
        uint256 index0Before = heap.indexes[accounts[0]];

        update(accounts[5], 16, 1);

        uint256 index5After = heap.indexes[accounts[5]];

        assertEq(index5Before, index5After);

        update(accounts[0], 20, 2);

        uint256 index0After = heap.indexes[accounts[0]];

        assertGt(index0After, index0Before);
    }

    function testIncreaseIndexChange() public {
        for (uint256 i = 0; i < 20; i++) update(accounts[i], 0, 20 - i);

        MAX_SORTED_USERS = 10;

        update(accounts[17], 20 - 17, 5);

        uint256 index17After = heap.indexes[accounts[17]];

        assertEq(index17After, 6);
    }

    function testIncreaseIndexChangeShiftUp() public {
        for (uint256 i = 0; i < 20; i++) update(accounts[i], 0, 20 - i);

        MAX_SORTED_USERS = 10;

        update(accounts[17], 20 - 17, 40);

        uint256 index17After = heap.indexes[accounts[17]];

        assertEq(index17After, 1);
    }

    function testRemoveLast() public {
        update(accounts[0], 0, 4);
        update(accounts[1], 0, 2);
        update(accounts[2], 0, 3);

        uint256 sizeBefore = heap.size;

        update(accounts[2], 3, 0);

        uint256 sizeAfter = heap.size;

        assertLt(sizeAfter, sizeBefore);
        assertEq(heap.accounts.length, 2);
    }

    function testRemoveShiftDown() public {
        for (uint256 i = 0; i < 20; i++) update(accounts[i], 0, NB_ACCOUNTS - i);

        update(accounts[5], NB_ACCOUNTS - 5, 0);

        assertEq(heap.accounts[5].value, NB_ACCOUNTS - 2 * (5 + 1) + 1);
    }

    function testRemoveShiftUp() public {
        update(accounts[0], 0, 40);
        update(accounts[1], 0, 10);
        update(accounts[2], 0, 30);
        update(accounts[3], 0, 8);
        update(accounts[4], 0, 7);
        update(accounts[5], 0, 25);

        assertEq(heap.accounts[0].value, 40);
        assertEq(heap.accounts[1].value, 10);
        assertEq(heap.accounts[2].value, 30);
        assertEq(heap.accounts[3].value, 8);
        assertEq(heap.accounts[4].value, 7);
        assertEq(heap.accounts[5].value, 25);

        update(accounts[3], 10, 0);

        assertEq(heap.accounts[1].value, 25);
    }
}
