// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

library BasicHeap {
    struct Account {
        address id;
        uint256 value;
    }

    struct Heap {
        Account[] accounts;
        mapping(address => uint256) indexes;
    }

    /// ERRORS ///

    /// @notice Thrown when the address is zero at insertion.
    error AddressIsZero();

    /// VIEW ///

    function length(Heap storage heap) internal view returns (uint256) {
        return heap.accounts.length;
    }

    function getValueOf(Heap storage heap, address _id) internal view returns (uint256) {
        uint256 index = heap.indexes[_id];
        if (index == 0) return 0;
        else return heap.accounts[index - 1].value;
    }

    function getHead(Heap storage heap) internal view returns (address) {
        if (heap.accounts.length > 0) return heap.accounts[0].id;
        else return address(0);
    }

    function getTail(Heap storage heap) internal view returns (address) {
        if (heap.accounts.length > 0) return heap.accounts[heap.accounts.length - 1].id;
        else return address(0);
    }

    function getPrev(Heap storage heap, address _id) internal view returns (address) {
        uint256 index = heap.indexes[_id];
        if (index > 1) return heap.accounts[index - 2].id;
        else return address(0);
    }

    function getNext(Heap storage heap, address _id) internal view returns (address) {
        uint256 index = heap.indexes[_id];
        if (index < heap.accounts.length) return heap.accounts[index].id;
        else return address(0);
    }

    /// PRIVATE ///

    function swap(
        Heap storage heap,
        uint256 index1,
        uint256 index2
    ) private {
        require(1 <= index1 && index1 <= heap.accounts.length, "SWAP index1 out of bounds");
        require(1 <= index2 && index2 <= heap.accounts.length, "SWAP index2 out of bounds");
        Account memory accountOldIndex1 = heap.accounts[index1 - 1];
        Account memory accountOldIndex2 = heap.accounts[index2 - 1];
        heap.accounts[index1 - 1] = accountOldIndex2;
        heap.accounts[index2 - 1] = accountOldIndex1;
        heap.indexes[accountOldIndex2.id] = index1;
        heap.indexes[accountOldIndex1.id] = index2;
    }

    function siftUp(Heap storage heap, uint256 index) private {
        uint256 mother = index / 2;
        while (mother > 0 && heap.accounts[index - 1].value > heap.accounts[mother - 1].value) {
            swap(heap, index, mother);
            mother = mother / 2;
        }
    }

    function siftDown(Heap storage heap, uint256 index) private {
        uint256 leftIndex;
        uint256 rightIndex;
        uint256 maxIndex;
        uint256 maxValue;
        while (true) {
            leftIndex = 2 * index;
            rightIndex = 2 * index + 1;
            maxIndex = index;
            maxValue = heap.accounts[index - 1].value;

            if (
                leftIndex <= heap.accounts.length && heap.accounts[leftIndex - 1].value > maxValue
            ) {
                maxIndex = leftIndex;
            }
            if (
                rightIndex <= heap.accounts.length && heap.accounts[rightIndex - 1].value > maxValue
            ) {
                maxIndex = rightIndex;
            }
            if (maxIndex != index) {
                swap(heap, index, maxIndex);
            } else break;
        }
    }

    function insert(
        Heap storage heap,
        address id,
        uint256 value
    ) private {
        if (id == address(0)) revert AddressIsZero();
        heap.accounts.push(Account(id, value));
        heap.indexes[id] = heap.accounts.length;
        siftUp(heap, heap.accounts.length);
    }

    function decrease(
        // only call with smaller value and when id is in the heap
        Heap storage heap,
        address id,
        uint256 newValue
    ) private {
        uint256 index = heap.indexes[id];
        heap.accounts[index - 1].value = newValue;
        siftDown(heap, index);
    }

    function increase(
        // only call with greater value and when id is in the heap
        Heap storage heap,
        address id,
        uint256 newValue
    ) private {
        uint256 index = heap.indexes[id];
        heap.accounts[index - 1].value = newValue;
        siftUp(heap, index);
    }

    function remove(Heap storage heap, address id) private {
        // only call when id is in the heap
        Account[] storage accounts = heap.accounts;
        uint256 index = heap.indexes[id];
        if (index == accounts.length) {
            accounts.pop();
            delete heap.indexes[id];
        } else {
            swap(heap, index, accounts.length);
            accounts.pop();
            delete heap.indexes[id];
            siftDown(heap, index);
        }
    }

    /// INTERNAL ///

    function update(
        Heap storage heap,
        address id,
        uint256 formerValue,
        uint256 newValue
    ) internal {
        if (formerValue != newValue) {
            if (newValue == 0) remove(heap, id);
            else if (formerValue == 0) insert(heap, id, newValue);
            else if (formerValue < newValue) increase(heap, id, newValue);
            else decrease(heap, id, newValue);
        }
    }
}
