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

    function load(Account[] storage accounts, uint256 index) public view returns (Account storage) {
        return accounts[index - 1];
    }

    function store(
        Account[] storage accounts,
        uint256 index,
        Account memory e
    ) public {
        accounts[index - 1] = e;
    }

    function swap(
        Heap storage heap,
        uint256 index1,
        uint256 index2
    ) internal {
        Account[] storage accounts = heap.accounts;
        mapping(address => uint256) storage indexes = heap.indexes;
        Account storage account_old_index1 = load(accounts, index1); // TODO : is storage needed here ?
        Account storage account_old_index2 = load(accounts, index2);
        store(accounts, index1, account_old_index2);
        store(accounts, index2, account_old_index1);
        indexes[account_old_index2.id] = index1;
        indexes[account_old_index1.id] = index2;
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

    function siftUp(Heap storage heap, uint256 index) internal {
        Account[] storage accounts = heap.accounts;
        require(index > 0 && index <= accounts.length, "index out of bounds (siftUp)");
        uint256 mother = parent(index);
        while (mother > 0 && load(accounts, index).value > load(accounts, mother).value) {
            swap(heap, index, mother);
            mother = parent(mother);
        }
    }

    function siftDown(Heap storage heap, uint256 index) internal {
        Account[] storage accounts = heap.accounts;
        require(index > 0 && index <= accounts.length, "index out of bounds (siftUp)");
        uint256 length = accounts.length;
        uint256 leftIndex;
        uint256 rightIndex;
        uint256 maxIndex;
        uint256 maxValue;
        while (true) {
            leftIndex = left(index);
            rightIndex = right(index);
            maxIndex = index;
            maxValue = load(accounts, index).value;

            if (leftIndex <= length && load(accounts, leftIndex).value > maxValue) {
                maxIndex = leftIndex;
            }
            if (rightIndex <= length && load(accounts, rightIndex).value > maxValue) {
                maxIndex = rightIndex;
            }
            if (maxIndex != index) {
                swap(heap, index, maxIndex);
            } else break;
        }
    }

    function get(Heap storage heap, address id) public view returns (uint256) {
        return heap.accounts[heap.indexes[id] - 1].value;
    }

    function insertOne(
        // rename into "insert"
        Heap storage heap,
        address id,
        uint256 value
    ) public {
        Account[] storage accounts = heap.accounts;
        Account memory acc = Account(id, value);
        accounts.push(acc);
        heap.indexes[id] = accounts.length;
        siftUp(heap, accounts.length);
    }

    function decrease(
        Heap storage heap,
        address id,
        uint256 toSubstract
    ) public {
        Account[] storage accounts = heap.accounts;
        uint256 index = heap.indexes[id];
        Account storage account = load(accounts, index);
        require(account.value > toSubstract, "should remove instead");
        account.value -= toSubstract;
        siftDown(heap, index);
    }

    function increase(
        Heap storage heap,
        address id,
        uint256 toAdd
    ) public {
        Account[] storage accounts = heap.accounts;
        uint256 index = heap.indexes[id];
        Account storage account = load(accounts, index);
        account.value += toAdd;
        siftUp(heap, index);
    }

    function removeOne(Heap storage heap, address id) public {
        // TODO : rename into "remove"
        Account[] storage accounts = heap.accounts;
        uint256 index = heap.indexes[id];
        swap(heap, index, accounts.length);
    }
}
