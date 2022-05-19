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

    function length(Heap storage _heap) internal view returns (uint256) {
        return _heap.accounts.length;
    }

    function getValueOf(Heap storage _heap, address _id) internal view returns (uint256) {
        uint256 index = _heap.indexes[_id];
        if (index == 0) return 0;
        else return _heap.accounts[index - 1].value;
    }

    function getHead(Heap storage _heap) internal view returns (address) {
        if (_heap.accounts.length > 0) return _heap.accounts[0].id;
        else return address(0);
    }

    function getTail(Heap storage _heap) internal view returns (address) {
        if (_heap.accounts.length > 0) return _heap.accounts[_heap.accounts.length - 1].id;
        else return address(0);
    }

    function getPrev(Heap storage _heap, address _id) internal view returns (address) {
        uint256 index = _heap.indexes[_id];
        if (index > 1) return _heap.accounts[index - 2].id;
        else return address(0);
    }

    function getNext(Heap storage _heap, address _id) internal view returns (address) {
        uint256 index = _heap.indexes[_id];
        if (index < _heap.accounts.length) return _heap.accounts[index].id;
        else return address(0);
    }

    /// PRIVATE ///

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

    function shiftUp(Heap storage _heap, uint256 _index) private {
        uint256 mother = _index / 2;
        while (mother > 0 && _heap.accounts[_index - 1].value > _heap.accounts[mother - 1].value) {
            swap(_heap, _index, mother);
            mother = mother / 2;
        }
    }

    function shiftDown(Heap storage _heap, uint256 _index) private {
        uint256 leftIndex;
        uint256 rightIndex;
        uint256 maxIndex;
        uint256 maxValue;
        while (true) {
            leftIndex = 2 * _index;
            rightIndex = 2 * _index + 1;
            maxIndex = _index;
            maxValue = _heap.accounts[_index - 1].value;

            if (
                leftIndex <= _heap.accounts.length && _heap.accounts[leftIndex - 1].value > maxValue
            ) {
                maxIndex = leftIndex;
            }
            if (
                rightIndex <= _heap.accounts.length &&
                _heap.accounts[rightIndex - 1].value > maxValue
            ) {
                maxIndex = rightIndex;
            }
            if (maxIndex != _index) {
                swap(_heap, _index, maxIndex);
            } else break;
        }
    }

    // only call when id is not in the _heap and with value != 0
    function insert(
        Heap storage _heap,
        address _id,
        uint256 _value
    ) private {
        // _heap cannot contain the 0 address
        if (_id == address(0)) revert AddressIsZero();
        _heap.accounts.push(Account(_id, _value));
        _heap.indexes[_id] = _heap.accounts.length;
        shiftUp(_heap, _heap.accounts.length);
    }

    // only when id is in the _heap with a value greater than newValue
    function decrease(
        Heap storage _heap,
        address _id,
        uint256 _newValue
    ) private {
        uint256 index = _heap.indexes[_id];
        _heap.accounts[index - 1].value = _newValue;
        shiftDown(_heap, index);
    }

    // only when id is in the _heap with a value smaller than newValue
    function increase(
        Heap storage _heap,
        address _id,
        uint256 _newValue
    ) private {
        uint256 index = _heap.indexes[_id];
        _heap.accounts[index - 1].value = _newValue;
        shiftUp(_heap, index);
    }

    // only call when id is in the _heap
    function remove(Heap storage _heap, address _id) private {
        Account[] storage accounts = _heap.accounts;
        uint256 index = _heap.indexes[_id];
        if (index == accounts.length) {
            accounts.pop();
            delete _heap.indexes[_id];
        } else {
            swap(_heap, index, accounts.length);
            accounts.pop();
            delete _heap.indexes[_id];
            shiftDown(_heap, index);
        }
    }

    /// INTERNAL ///

    // only call with id in the _heap,with value formerValue
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
