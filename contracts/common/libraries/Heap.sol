// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

library BasicHeap {
    struct Account {
        address id;
        uint256 value;
    }

    function load(Account[] storage heap, uint256 index) public view returns (Account storage) {
        return heap[index - 1];
    }

    function store(
        Account[] storage heap,
        uint256 index,
        Account storage e
    ) public {
        heap[index - 1] = e;
    }

    function swap(
        Account[] storage heap,
        uint256 index1,
        uint256 index2
    ) internal {
        Account storage heap_index1 = load(heap, index1);
        store(heap, index1, load(heap, index2));
        store(heap, index2, heap_index1);
    }

    function left(uint256 index) public pure returns (uint256) {
        return 2 * index;
    }

    function right(uint256 index) public pure returns (uint256) {
        return 2 * index + 1;
    }

    function parent(uint256 index) public pure returns (uint256) {
        return index / 2;
    }

    function siftUp(Account[] storage heap, uint256 index) internal {
        require(index > 0 && index <= heap.length, "index out of bounds (siftUp)");
        uint256 mother = parent(index);
        while (mother > 0 && load(heap, index).value > load(heap, mother).value) {
            swap(heap, index, mother);
            mother = parent(mother);
        }
    }

    function siftDown(Account[] storage heap, uint256 index) internal {
        require(index > 0 && index <= heap.length, "index out of bounds (siftUp)");
        uint256 length = heap.length;
        uint256 leftIndex;
        uint256 rightIndex;
        uint256 maxIndex;
        uint256 maxValue;
        while (true) {
            leftIndex = left(index);
            rightIndex = right(index);
            maxIndex = index;
            maxValue = load(heap, index).value;

            if (leftIndex <= length && load(heap, leftIndex).value > maxValue) {
                maxIndex = leftIndex;
            }
            if (rightIndex <= length && load(heap, rightIndex).value > maxValue) {
                maxIndex = rightIndex;
            }
            if (maxIndex != index) {
                swap(heap, index, maxIndex);
            } else break;
        }
    }
}
