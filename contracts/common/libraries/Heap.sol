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

    /// @notice Returns the length of the `_heap`.
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
        _heap.accounts[_index1 - 1] = accountOldIndex2;
        _heap.accounts[_index2 - 1] = accountOldIndex1;
        _heap.indexes[accountOldIndex2.id] = _index1;
        _heap.indexes[accountOldIndex1.id] = _index2;
    }

    /// @notice Moves an account up the heap until its value is smaller than its parent's.
    /// @dev This functions restores the invariant about the order of the values stored when the account at `_index` is the only one with value greater than what it should be.
    /// @param _heap The heap to modify.
    /// @param _index The index of the account to move.
    function shiftUp(Heap storage _heap, uint256 _index) private {
        uint256 mother = _index / 2;
        while (mother > 0 && _heap.accounts[_index - 1].value > _heap.accounts[mother - 1].value) {
            swap(_heap, _index, mother);
            mother = mother / 2;
        }
    }

    /// @notice Moves an account down the heap until its value is greater than the ones of its children.
    /// @dev This functions restores the invariant about the order of the values stored when the account at `_index` is the only one with value smaller than what it should be.
    /// @param _heap The heap to modify.
    /// @param _index The index of the account to move.
    function shiftDown(Heap storage _heap, uint256 _index) private {
        uint256 accountsLength = _heap.accounts.length;
        uint256 leftIndex;
        uint256 rightIndex;
        uint256 maxIndex;
        uint256 maxValue;

        while (true) {
            leftIndex = 2 * _index;
            rightIndex = 2 * _index + 1;
            maxIndex = _index;
            maxValue = _heap.accounts[_index - 1].value;

            if (leftIndex <= accountsLength && _heap.accounts[leftIndex - 1].value > maxValue)
                maxIndex = leftIndex;

            if (rightIndex <= accountsLength && _heap.accounts[rightIndex - 1].value > maxValue)
                maxIndex = rightIndex;

            if (maxIndex != _index) swap(_heap, _index, maxIndex);
            else break;
        }
    }

    /// @notice Inserts an account in the `_heap`.
    /// @dev Only call this function when `_id`.
    /// @dev Reverts with AddressIsZero if `_value` is 0.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to insert.
    /// @param _value The value of the account to insert.
    function insert(
        Heap storage _heap,
        address _id,
        uint256 _value
    ) private {
        // _heap cannot contain the 0 address
        if (_id == address(0)) revert AddressIsZero();
        _heap.accounts.push(Account(_id, _value));
        uint256 accountsLength = _heap.accounts.length;
        _heap.indexes[_id] = accountsLength;
        shiftUp(_heap, accountsLength);
    }

    /// @notice Increase the amount of an account in the `_heap`.
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
        shiftDown(_heap, index);
    }

    /// @notice Increase the amount of an account in the `_heap`.
    /// @dev Only call this function when `_id` is in the `_heap` with a smaller value than `_newValue`.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to increase the amount.
    /// @param _newValue The new value of the account.
    function increase(
        Heap storage _heap,
        address _id,
        uint256 _newValue
    ) private {
        uint256 index = _heap.indexes[_id];
        _heap.accounts[index - 1].value = _newValue;
        shiftUp(_heap, index);
    }

    /// @notice Removes an account in the `_heap`.
    /// @dev Only call when `_id` is in the `_heap`.
    /// @param _heap The heap to modify.
    /// @param _id The address of the account to remove.
    function remove(Heap storage _heap, address _id) private {
        uint256 index = _heap.indexes[_id];
        uint256 accountsLength = _heap.accounts.length;
        if (index == accountsLength) {
            _heap.accounts.pop();
            delete _heap.indexes[_id];
        } else {
            swap(_heap, index, accountsLength);
            _heap.accounts.pop();
            delete _heap.indexes[_id];
            shiftDown(_heap, index);
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
        uint256 _newValue
    ) internal {
        if (_formerValue != _newValue) {
            if (_newValue == 0) remove(_heap, _id);
            else if (_formerValue == 0) insert(_heap, _id, _newValue);
            else if (_formerValue < _newValue) increase(_heap, _id, _newValue);
            else decrease(_heap, _id, _newValue);
        }
    }
}
