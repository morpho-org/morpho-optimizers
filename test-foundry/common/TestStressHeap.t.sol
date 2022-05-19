// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "forge-std/stdlib.sol";

import "@contracts/common/libraries/Heap.sol";

contract TestStressHeap is DSTest {
    using BasicHeap for BasicHeap.Heap;

    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public TESTED_SIZE = 600;
    address public ADDR_ZERO = address(0);

    BasicHeap.Heap internal heap;

    uint256 public NDS = 50;
    address[] public ids;

    function setUp() public {
        heap.accounts.push(BasicHeap.Account(address(this), TESTED_SIZE));
        heap.indexes[address(this)] = 1;
        for (uint256 i = 1; i < TESTED_SIZE; i++) {
            address id = address(uint160(heap.accounts[i - 1].id) + 1);
            heap.accounts.push(BasicHeap.Account(id, TESTED_SIZE - i));
            heap.indexes[id] = heap.accounts.length;
        }

        ids = new address[](NDS);
        ids[0] = address(1);
        for (uint256 i = 1; i < NDS; i++) {
            ids[i] = address(uint160(ids[i - 1]) + 1);
        }
    }

    function testAddOneTop() public {
        heap.update(ids[0], 0, TESTED_SIZE - 1);
    }

    function testAddOneMiddle() public {
        heap.update(ids[0], 0, TESTED_SIZE / 2);
    }

    function testAddOneBottom() public {
        heap.update(ids[0], 0, 1);
    }

    function testRemoveTop() public {
        heap.update(heap.accounts[0].id, heap.accounts[0].value, 0);
    }

    function testRemoveMiddle() public {
        uint256 middle = TESTED_SIZE / 2;
        heap.update(heap.accounts[middle].id, heap.accounts[middle].value, 0);
    }

    function testRemoveEnd() public {
        uint256 end = TESTED_SIZE - 10;
        heap.update(heap.accounts[end].id, heap.accounts[end].value, 0);
    }

    function testIncreaseTop() public {
        heap.update(heap.accounts[0].id, heap.accounts[0].value, heap.accounts[0].value + 5);
    }

    function testIncreaseMiddle() public {
        uint256 middle = TESTED_SIZE / 2;
        heap.update(
            heap.accounts[middle].id,
            heap.accounts[middle].value,
            heap.accounts[middle].value + 5
        );
    }

    function testIncreaseEnd() public {
        uint256 end = TESTED_SIZE - 10;
        heap.update(heap.accounts[end].id, heap.accounts[end].value, heap.accounts[end].value + 5);
    }

    function testDecreaseTop() public {
        heap.update(heap.accounts[0].id, heap.accounts[0].value, heap.accounts[0].value - 5);
    }

    function testDecreaseMiddle() public {
        uint256 middle = TESTED_SIZE / 2;
        heap.update(
            heap.accounts[middle].id,
            heap.accounts[middle].value,
            heap.accounts[middle].value - 5
        );
    }

    function testDecreaseEnd() public {
        uint256 end = TESTED_SIZE - 10;
        heap.update(heap.accounts[end].id, heap.accounts[end].value, heap.accounts[end].value - 5);
    }
}
