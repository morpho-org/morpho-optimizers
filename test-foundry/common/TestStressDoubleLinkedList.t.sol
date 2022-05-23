// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "ds-test/test.sol";

import "@contracts/common/libraries/DoubleLinkedList.sol";

contract ListStorage {
    DoubleLinkedList.List internal list;
    uint256 public TESTED_SIZE = 10000;
    uint256 public MAX_SORTED_USERS = 100;
    uint256 public incrementAmount = 5;

    function setUp() public {
        list.head = address(uint160(1));
        list.accounts[list.head] = DoubleLinkedList.Account(address(0), address(0), TESTED_SIZE);

        address prev = list.head;
        address current;

        for (uint256 i = 1; i < TESTED_SIZE; i++) {
            current = address(uint160(i + 1));
            list.accounts[current] = DoubleLinkedList.Account(prev, address(0), TESTED_SIZE - i);
            list.accounts[prev].next = current;
            prev = current;
        }
        list.tail = current;
    }

    function update(
        address _id,
        uint256 _formerValue,
        uint256 _newValue
    ) public {
        if (_formerValue != _newValue) {
            if (_newValue == 0) DoubleLinkedList.remove(list, _id);
            else if (_formerValue == 0)
                DoubleLinkedList.insertSorted(list, _id, _newValue, MAX_SORTED_USERS);
            else {
                DoubleLinkedList.remove(list, _id);
                DoubleLinkedList.insertSorted(list, _id, _newValue, MAX_SORTED_USERS);
            }
        }
    }
}

contract TestStressDoubleLinkedList is DSTest {
    using DoubleLinkedList for DoubleLinkedList.List;

    ListStorage public ls = new ListStorage();
    uint256 public ts;
    uint256 public im;

    function setUp() public {
        ls.setUp();
        ts = ls.TESTED_SIZE();
        im = ls.incrementAmount();
    }

    function testInsertOneTop() public {
        ls.update(address(this), 0, ts + 1);
    }

    function testInsertOneMiddle() public {
        ls.update(address(this), 0, ts / 2);
    }

    function testInsertOneBottom() public {
        ls.update(address(this), 0, 1);
    }

    function testRemoveOneTop() public {
        ls.update(address(uint160(1)), ts, 0);
    }

    function testRemoveOneMiddle() public {
        uint256 middle = ts / 2;
        ls.update(address(uint160(middle + 1)), ts - middle, 0);
    }

    function testRemoveOneBottom() public {
        uint256 end = ts - 2 * im;
        ls.update(address(uint160(end + 1)), ts - end, 0);
    }

    function testIncreaseOneTop() public {
        ls.update(address(uint160(1)), ts, ts + im);
    }

    function testIncreaseOneMiddle() public {
        uint256 middle = ts / 2;
        ls.update(address(uint160(middle + 1)), ts - middle, ts - middle + im);
    }

    function testIncreaseOneBottom() public {
        uint256 end = ts - 2 * im;
        ls.update(address(uint160(end + 1)), ts - end, ts - end + im);
    }

    function testDecreaseOneTop() public {
        ls.update(address(uint160(1)), ts, 1);
    }

    function testDecreaseOneMiddle() public {
        uint256 middle = ts / 2;
        ls.update(address(uint160(middle + 1)), ts - middle, 1);
    }

    function testDecreaseOneBottom() public {
        uint256 end = ts - 2 * im;
        ls.update(address(uint160(end + 1)), ts - end, ts - end - im);
    }
}
