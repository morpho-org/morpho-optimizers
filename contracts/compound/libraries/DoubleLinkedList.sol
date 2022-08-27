// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

library DoubleLinkedList {
    /// STRUCTS ///

    struct Account {
        address prev;
        address next;
        uint256 value;
    }

    struct List {
        mapping(address => Account) accounts;
    }

    /// ERRORS ///

    /// @notice Thrown when the account is already inserted in the double linked list.
    error AccountAlreadyInserted();

    /// @notice Thrown when the account to remove does not exist.
    error AccountDoesNotExist();

    /// @notice Thrown when the address is zero at insertion.
    error AddressIsZero();

    /// @notice Thrown when the value is zero at insertion.
    error ValueIsZero();

    /// INTERNAL ///

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
        return _list.accounts[address(0)].next;
    }

    /// @notice Returns the address at the tail of the `_list`.
    /// @param _list The list to get the tail.
    /// @return The address of the tail.
    function getTail(List storage _list) internal view returns (address) {
        return _list.accounts[address(0)].prev;
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
        if (_list.accounts[_id].value == 0) revert AccountDoesNotExist();
        Account memory account = _list.accounts[_id];

        if (account.prev != address(0)) _list.accounts[account.prev].next = account.next;
        else _list.accounts[address(0)].next = account.next;
        if (account.next != address(0)) _list.accounts[account.next].prev = account.prev;
        else _list.accounts[address(0)].prev = account.prev;

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
        if (_value == 0) revert ValueIsZero();
        if (_id == address(0)) revert AddressIsZero();
        if (_list.accounts[_id].value != 0) revert AccountAlreadyInserted();

        uint256 numberOfIterations;
        address next = _list.accounts[address(0)].next; // `_id` will be inserted before `next`.

        while (next != address(0) && _list.accounts[next].value >= _value) {
            next = _list.accounts[next].next;
            unchecked {
                ++numberOfIterations;
            }
        }
        if (numberOfIterations == _maxIterations) {
            next = address(0);
        }

        _list.accounts[_id] = Account(_list.accounts[next].prev, next, _value);
        _list.accounts[_list.accounts[next].prev].next = _id;
        _list.accounts[next].prev = _id;
    }
}
