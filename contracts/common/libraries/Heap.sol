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

    function length(Heap storage heap) internal view returns (uint256) {
        return heap.accounts.length;
    }

    function getValueOf(Heap storage heap, address _id) internal view returns (uint256) {
        uint256 index = heap.indexes[_id];
        if (index == 0) return 0;
        else return heap.accounts[index - 1].value;
    }

    function getHead(Heap storage heap) internal view returns (address) {
        if (heap.accounts.length == 0) return address(0);
        else return heap.accounts[0].id;
    }

    function getTail(Heap storage heap) internal view returns (address) {
        require(heap.accounts.length > 0, "empty HEAP");
        return heap.accounts[heap.accounts.length - 1].id;
    }

    function getNext(Heap storage heap, address _id) internal view returns (address) {
        return heap.accounts[heap.indexes[_id]].id;
    }

    function load(Account[] storage accounts, uint256 index) private view returns (Account memory) {
        require(1 <= index && index <= accounts.length, "LOAD index out of bounds");
        return accounts[index - 1];
    }

    function store(
        Account[] storage accounts,
        uint256 index,
        Account memory e
    ) private {
        require(1 <= index && index <= accounts.length, "STORE index out of bounds");
        accounts[index - 1] = e;
    }

    function swap(
        Heap storage heap,
        uint256 index1,
        uint256 index2
    ) private {
        require(1 <= index1 && index1 <= heap.accounts.length, "SWAP index1 out of bounds");
        require(1 <= index2 && index2 <= heap.accounts.length, "SWAP index2 out of bounds");
        Account[] storage accounts = heap.accounts;
        mapping(address => uint256) storage indexes = heap.indexes;
        Account memory account_old_index1 = load(accounts, index1);
        Account memory account_old_index2 = load(accounts, index2);
        store(accounts, index1, account_old_index2);
        store(accounts, index2, account_old_index1);
        indexes[account_old_index2.id] = index1;
        indexes[account_old_index1.id] = index2;
    }

    function left(uint256 index) private pure returns (uint256) {
        return 2 * index;
    }

    function right(uint256 index) private pure returns (uint256) {
        return 2 * index + 1;
    }

    function parent(uint256 index) private pure returns (uint256) {
        return index / 2;
    }

    function siftUp(Heap storage heap, uint256 index) private {
        Account[] storage accounts = heap.accounts;
        require(index > 0 && index <= accounts.length, "SIFTUP index out of bounds");
        uint256 mother = parent(index);
        while (mother > 0 && load(accounts, index).value > load(accounts, mother).value) {
            swap(heap, index, mother);
            mother = parent(mother);
        }
    }

    function siftDown(Heap storage heap, uint256 index) private {
        Account[] storage accounts = heap.accounts;
        require(index > 0 && index <= accounts.length, "SIFTDOWN index out of bounds");
        uint256 leftIndex;
        uint256 rightIndex;
        uint256 maxIndex;
        uint256 maxValue;
        while (true) {
            leftIndex = left(index);
            rightIndex = right(index);
            maxIndex = index;
            maxValue = load(accounts, index).value;

            if (leftIndex <= accounts.length && load(accounts, leftIndex).value > maxValue) {
                maxIndex = leftIndex;
            }
            if (rightIndex <= accounts.length && load(accounts, rightIndex).value > maxValue) {
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
        Account[] storage accounts = heap.accounts;
        Account memory acc = Account(id, value);
        accounts.push(acc);
        heap.indexes[id] = accounts.length;
        siftUp(heap, accounts.length);
    }

    function decrease(
        // only call with smaller value and when id is in the heap
        Heap storage heap,
        address id,
        uint256 newValue
    ) private {
        Account[] storage accounts = heap.accounts;
        uint256 index = heap.indexes[id];
        Account memory account = load(accounts, index);
        account.value = newValue;
        siftDown(heap, index);
    }

    function increase(
        // only call with greater value and when id is in the heap
        Heap storage heap,
        address id,
        uint256 newValue
    ) private {
        Account[] storage accounts = heap.accounts;
        uint256 index = heap.indexes[id];
        Account memory account = load(accounts, index);
        account.value = newValue;
        siftUp(heap, index);
    }

    function remove(Heap storage heap, address id) private {
        // only call when id is in the heap
        Account[] storage accounts = heap.accounts;
        uint256 index = heap.indexes[id];
        require(index != 0, "remove on non-present element");
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

    function updateHeap(
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
