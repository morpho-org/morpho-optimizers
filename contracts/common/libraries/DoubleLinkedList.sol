// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

library DoubleLinkedList {
    struct Account {
        address prev;
        address next;
        uint256 value;
    }

    struct List {
        mapping(address => Account) accounts;
        address head;
        address tail;
    }

    /// @notice Returns the `account` linked to `_id`.
    /// @param _list The list to search in.
    /// @param _id The address of the account.
    /// @return The value of the account.
    function getValueOf(List storage _list, address _id) internal view returns (uint256) {
        return _list.accounts[_id].value;
    }

    /// @notice Returns the address at the head of the `_list`.
    /// @param _list The list to get the head.
    /// @return The address of the head.
    function getHead(List storage _list) internal view returns (address) {
        return _list.head;
    }

    /// @notice Returns the address at the tail of the `_list`.
    /// @param _list The list to get the tail.
    /// @return The address of the tail.
    function getTail(List storage _list) internal view returns (address) {
        return _list.tail;
    }

    /// @notice Returns the next id address from the current `_id`.
    /// @param _list The list to search in.
    /// @param _id The address of the account.
    /// @return The address of the next account.
    function getNext(List storage _list, address _id) internal view returns (address) {
        return _list.accounts[_id].next;
    }

    /// @notice Returns the previous id address from the current `_id`.
    /// @param _list The list to search in.
    /// @param _id The address of the account.
    /// @return The address of the previous account.
    function getPrev(List storage _list, address _id) internal view returns (address) {
        return _list.accounts[_id].prev;
    }

    /// @notice Removes an account of the `_list`.
    /// @param _list The list to search in.
    /// @param _id The address of the account.
    function remove(List storage _list, address _id) internal {
        require(_list.accounts[_id].value != 0, "DLL: account must exist");
        Account memory account = _list.accounts[_id];

        if (account.prev != address(0)) _list.accounts[account.prev].next = account.next;
        else _list.head = account.next;
        if (account.next != address(0)) _list.accounts[account.next].prev = account.prev;
        else _list.tail = account.prev;

        delete _list.accounts[_id];
    }

    /// @notice Inserts an account in the `_list` at the right slot based on its `_value`.
    /// @param _list The list to search in.
    /// @param _id The address of the account.
    /// @param _value The value of the account.
    /// @param _maxIterations The max number of iterations.
    function insertSorted(
        List storage _list,
        address _id,
        uint256 _value,
        uint256 _maxIterations
    ) internal {
        require(_value != 0, "DLL: _value must be != 0");
        require(_list.accounts[_id].value == 0, "DLL: account already created");

        uint256 numberOfIterations;
        address current = _list.head;
        while (
            numberOfIterations < _maxIterations &&
            current != _list.tail &&
            _list.accounts[current].value >= _value
        ) {
            current = _list.accounts[current].next;
            unchecked {
                ++numberOfIterations;
            }
        }

        address nextId;
        address prevId;
        if (_list.accounts[current].value < _value) {
            prevId = _list.accounts[current].prev;
            nextId = current;
        } else prevId = _list.tail;

        _list.accounts[_id] = Account(prevId, nextId, _value);

        if (prevId != address(0)) _list.accounts[prevId].next = _id;
        else _list.head = _id;
        if (nextId != address(0)) _list.accounts[nextId].prev = _id;
        else _list.tail = _id;
    }
}
