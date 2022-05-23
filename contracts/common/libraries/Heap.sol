// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

library BasicHeap {
    struct Account {
        address id; // The address of the account owner.
        uint256 value; // The value of the account.
    }

    struct Heap {
        Account[] accounts; // All the accounts.
        uint256 size; // The size of the heap portion of the structure, should be less than accounts length.
        mapping(address => uint256) indexes; // A mapping from an address to an index in accounts.
    }

    /// ERRORS ///

    /// @notice Thrown when the address is zero at insertion.
    error AddressIsZero();

    /// PURE ///

    /// @notice Computes a new suitable size from `_size` that is smaller than `_maxSortedUsers`.
    /// @dev We use division by 2 because the biggest elements of the heap are in the first half (rounded down) of the heap.
    /// @param _size The old size of the heap.
    /// @param _maxSortedUsers The maximum size of the heap.
    /// @return The new size computed.
    function computeSize(uint256 _size, uint256 _maxSortedUsers) public pure returns (uint256) {
        while (_size >= _maxSortedUsers) _size /= 2;
        return _size;
    }

    /// VIEW ///

    /// @notice Returns the number of users in the `_heap`.
    /// @param _heap The heap parameter.
    /// @return The length of the heap.
    function length(Heap storage _heap) internal view returns (uint256) {
        return _heap.accounts.length;
    }

    /// @notice Returns the value of the account linked to `_id`.
    /// @param _heap The heap to search in.
    /// @param _id The address of the account.
    /// @return The value of the account.
    function getValueOf(Heap storage _heap, address _id) internal view returns (uint256) {
        uint256 index = _heap.indexes[_id];
        if (index == 0) return 0;
        else return _heap.accounts[index - 1].value;
    }

    /// @notice Returns the address at the head of the `_heap`.
    /// @param _heap The heap to get the head.
    /// @return The address of the head.
    function getHead(Heap storage _heap) internal view returns (address) {
        if (_heap.accounts.length > 0) return _heap.accounts[0].id;
        else return address(0);
    }

    /// @notice Returns the address at the tail of the `_heap`.
    /// @param _heap The heap to get the tail.
    /// @return The address of the tail.
    function getTail(Heap storage _heap) internal view returns (address) {
        if (_heap.accounts.length > 0) return _heap.accounts[_heap.accounts.length - 1].id;
        else return address(0);
    }

    /// @notice Returns the previous address from the current `_id`.
    /// @param _heap The heap to search in.
    /// @param _id The address of the account.
    /// @return The address of the previous account.
    function getPrev(Heap storage _heap, address _id) internal view returns (address) {
        uint256 index = _heap.indexes[_id];
        if (index > 1) return _heap.accounts[index - 2].id;
        else return address(0);
    }

    /// @notice Returns the next address from the current `_id`.
    /// @param _heap The heap to search in.
    /// @param _id The address of the account.
    /// @return The address of the next account.
    function getNext(Heap storage _heap, address _id) internal view returns (address) {
        uint256 index = _heap.indexes[_id];
        if (index < _heap.accounts.length) return _heap.accounts[index].id;
        else return address(0);
    }

    /// PRIVATE ///

    /// @notice Sets `_index` in the `_heap` to be `_account`.
    /// @dev The heap may lose its invariant about the order of the values stored.
    /// @dev Only call this function with an index in the bounds of the array.
    /// @param _heap The heap to modify.
    /// @param _index The index of the account in the heap to be set.
    /// @param _account The account to set the `_index` to.
    function set(
        Heap storage _heap,
        uint256 _index,
        Account memory _account
    ) private {
        _heap.accounts[_index - 1] = _account;
        _heap.indexes[_account.id] = _index;
    }

    /// @notice Swaps two accounts in the `_heap`.
    /// @dev The heap may lose its invariant about the order of the values stored.
    /// @dev Only call this function with indexes in the bounds of the array.
    /// @param _heap The heap to modify.
    /// @param _index1 The index of the first account in the heap.
    /// @param _index2 The index of the second account in the heap.
    function swap(
        Heap storage _heap,
        uint256 _index1,
        uint256 _index2
    ) private {
        Account memory accountOldIndex1 = _heap.accounts[_index1 - 1];
        Account memory accountOldIndex2 = _heap.accounts[_index2 - 1];
        set(_heap, _index1, accountOldIndex2);
        set(_heap, _index2, accountOldIndex1);
    }

    /// @notice Moves an account up the heap until its value is smaller than the one of its parent.
    /// @dev This functions restores the invariant about the order of the values stored when the account at `_index` is the only one with value greater than what it should be.
    /// @param _heap The heap to modify.
    /// @param _index The index of the account to move.
    function shiftUp(Heap storage _heap, uint256 _index) private {
        Account memory initAccount = _heap.accounts[_index - 1];
        uint256 initValue = initAccount.value;
        while (_index != 1 && initValue > _heap.accounts[_index / 2 - 1].value) {
            set(_heap, _index, _heap.accounts[_index / 2 - 1]);
            _index /= 2;
        }
        set(_heap, _index, initAccount);
    }

    /// @notice Moves an account down the heap until its value is greater than the ones of its children.
    /// @dev This functions restores the invariant about the order of the values stored when the account at `_index` is the only one with value smaller than what it should be.
    /// @param _heap The heap to modify.
    /// @param _index The index of the account to move.
    function shiftDown(Heap storage _heap, uint256 _index) private {
        uint256 size = _heap.size;
        Account memory initAccount = _heap.accounts[_index - 1];
        uint256 childIndex = _index * 2;
        Account memory childAccount;

        while (childIndex <= size) {
            if (
                // Compute the index of the child with biggest value.
                childIndex + 1 <= size &&
                _heap.accounts[childIndex].value > _heap.accounts[childIndex - 1].value
            ) childIndex++;

            childAccount = _heap.accounts[childIndex - 1];

            if (childAccount.value > initAccount.value) {
                set(_heap, _index, childAccount);
                _index = childIndex;
                childIndex *= 2;
            } else break;
        }
        set(_heap, _index, initAccount);
    }

    /// @notice Inserts an account in the `_heap`.
    /// @dev Only call this function when `_id`.
    /// @dev Reverts with AddressIsZero if `_value` is 0.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to insert.
    /// @param _value The value of the account to insert.
    /// @param _maxSortedUsers The maximum size of the heap.
    function insert(
        Heap storage _heap,
        address _id,
        uint256 _value,
        uint256 _maxSortedUsers
    ) private {
        // `_heap` cannot contain the 0 address
        if (_id == address(0)) revert AddressIsZero();
        uint256 size = _heap.size;
        _heap.accounts.push(Account(_id, _value));
        uint256 accountsLength = _heap.accounts.length;
        _heap.indexes[_id] = accountsLength;
        swap(_heap, size + 1, accountsLength);
        shiftUp(_heap, size + 1);
        _heap.size = computeSize(size, _maxSortedUsers);
    }

    /// @notice Decreases the amount of an account in the `_heap`.
    /// @dev Only call this function when `_id` is in the `_heap` with a value greater than `_newValue`.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to decrease the amount.
    /// @param _newValue The new value of the account.
    function decrease(
        Heap storage _heap,
        address _id,
        uint256 _newValue
    ) private {
        uint256 index = _heap.indexes[_id];
        _heap.accounts[index - 1].value = _newValue;
        if (index <= _heap.size) shiftDown(_heap, index);
    }

    /// @notice Increases the amount of an account in the `_heap`.
    /// @dev Only call this function when `_id` is in the `_heap` with a smaller value than `_newValue`.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to increase the amount.
    /// @param _newValue The new value of the account.
    function increase(
        Heap storage _heap,
        address _id,
        uint256 _newValue,
        uint256 _maxSortedUsers
    ) private {
        uint256 index = _heap.indexes[_id];
        _heap.accounts[index - 1].value = _newValue;
        uint256 size = _heap.size;
        if (index <= size) shiftUp(_heap, index);
        else if (size < _heap.accounts.length) {
            swap(_heap, size + 1, index);
            shiftUp(_heap, size + 1);
            _heap.size = computeSize(size, _maxSortedUsers);
        }
    }

    /// @notice Removes an account in the `_heap`.
    /// @dev Only call when `_id` is in the `_heap` with value `_removedValue`.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to remove.
    /// @param _removedValue The value of the account to remove.
    function remove(
        Heap storage _heap,
        address _id,
        uint256 _removedValue
    ) private {
        uint256 index = _heap.indexes[_id];
        uint256 accountsLength = _heap.accounts.length;
        swap(_heap, index, accountsLength);
        if (_heap.size == accountsLength) _heap.size--;
        _heap.accounts.pop();
        delete _heap.indexes[_id];
        if (index <= _heap.size) {
            if (_removedValue < _heap.accounts[index - 1].value) shiftDown(_heap, index);
            else shiftUp(_heap, index);
        }
    }

    /// INTERNAL ///

    /// @notice Removes an account in the `_heap`.
    /// @dev Only call with `_id` is in the `_heap` with value `_formerValue`.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to remove.
    function update(
        Heap storage _heap,
        address _id,
        uint256 _formerValue,
        uint256 _newValue,
        uint256 _maxSortedUsers
    ) internal {
        uint256 size = _heap.size;
        uint256 newSize = computeSize(size, _maxSortedUsers);
        if (size != newSize) _heap.size = newSize;
        if (_formerValue != _newValue) {
            if (_newValue == 0) remove(_heap, _id, _formerValue);
            else if (_formerValue == 0) insert(_heap, _id, _newValue, _maxSortedUsers);
            else if (_formerValue < _newValue) increase(_heap, _id, _newValue, _maxSortedUsers);
            else decrease(_heap, _id, _newValue);
        }
    }
}
