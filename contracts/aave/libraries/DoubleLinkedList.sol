// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

library DoubleLinkedList {
    struct Account {
        address id;
        address next;
        address prev;
        uint256 value;
        bool isIn;
    }

    struct List {
        mapping(address => Account) accounts;
        address head;
        address tail;
        uint256 counter;
    }

    /** @dev Returns the `account` linked to `_id`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return account The account linked to `_id`.
     */
    function get(List storage _list, address _id) internal view returns (Account memory account) {
        return _list.accounts[_id];
    }

    /** @dev Returns the `account` linked to `_id`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return value The value of the account.
     */
    function getValueOf(List storage _list, address _id) internal view returns (uint256) {
        return _list.accounts[_id].value;
    }

    /** @dev Returns the next id address from the current `_id`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return account The account linked to `_id`.
     */
    function getNext(List storage _list, address _id) internal view returns (address) {
        return _list.accounts[_id].next;
    }

    /** @dev Adds an `_id` and its value to the head of the `_list`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @param _value The value of the account.
     *  @return bool Whether the account has been added or not.
     */
    function addHead(
        List storage _list,
        address _id,
        uint256 _value
    ) internal returns (bool) {
        if (!_contains(_list, _id)) {
            _createAccount(_list, _id, _value);
            _link(_list, _id, _list.head);
            _setHead(_list, _id);
            if (_list.tail == address(0)) _setTail(_list, _id);
            return true;
        } else {
            return false;
        }
    }

    /** @dev Adds an `_id` and its value to the tail of the `_list`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @param _value The value of the account.
     *  @return bool Whether the account has been added or not.
     */
    function addTail(
        List storage _list,
        address _id,
        uint256 _value
    ) internal returns (bool) {
        if (!_contains(_list, _id)) {
            if (_list.head == address(0)) {
                addHead(_list, _id, _value);
            } else {
                _createAccount(_list, _id, _value);
                _link(_list, _list.tail, _id);
                _setTail(_list, _id);
            }
            return true;
        } else {
            return false;
        }
    }

    /** @dev Removes an account of the `_list`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return bool Whether the account has been removed or not.
     */
    function remove(List storage _list, address _id) internal returns (bool) {
        if (_contains(_list, _id)) {
            Account memory account = _list.accounts[_id];
            if (_list.head == _id && _list.tail == _id) {
                _setHead(_list, address(0));
                _setTail(_list, address(0));
            } else if (_list.head == _id) {
                _setHead(_list, account.next);
                _list.accounts[account.next].prev = address(0);
            } else if (_list.tail == _id) {
                _setTail(_list, account.prev);
                _list.accounts[account.prev].next = address(0);
            } else {
                _link(_list, account.prev, account.next);
            }
            _list.counter -= 1;
            delete _list.accounts[account.id];
            return true;
        } else {
            return false;
        }
    }

    /** @dev Inserts an account in the `_list` at the right slot based on its `_value`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @param _value The value of the account.
     *  @param _maxIterations The max number of iterations.
     */
    function insertSorted(
        List storage _list,
        address _id,
        uint256 _value,
        uint256 _maxIterations
    ) internal {
        require(!_contains(_list, _id));
        address current = _list.head;
        uint256 numberOfIterations;
        while (
            numberOfIterations <= _maxIterations &&
            current != _list.tail &&
            _list.accounts[current].value > _value
        ) {
            current = _list.accounts[current].next;
            numberOfIterations++;
        }
        if (numberOfIterations == _maxIterations + 1) {
            require(addTail(_list, _id, _value));
        } else {
            require(insertBefore(_list, current, _id, _value));
        }
    }

    /** @dev Inserts an account in the `_list` before `_nextId`.
     *  @param _list The list to search in.
     *  @param _nextId The account id from which to insert the account before.
     *  @param _id The address of the account.
     *  @param _value The value of the account.
     */
    function insertBefore(
        List storage _list,
        address _nextId,
        address _id,
        uint256 _value
    ) internal returns (bool) {
        require(!_contains(_list, _id));
        if (_nextId == _list.tail) {
            return addTail(_list, _id, _value);
        } else {
            Account memory nextAccount = _list.accounts[_nextId];
            Account memory prevAccount = _list.accounts[nextAccount.prev];
            _createAccount(_list, _id, _value);
            _link(_list, _id, nextAccount.id);
            _link(_list, prevAccount.id, _id);
            return true;
        }
    }

    /** @dev Returns whether or not the account is in the `_list`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return whether or not the account is in the `_list`.
     */
    function contains(List storage _list, address _id) internal view returns (bool) {
        return _contains(_list, _id);
    }

    /** @dev Returns the length of the `_list`.
     *  @param _list The list to get the length.
     *  @return The length.
     */
    function length(List storage _list) internal view returns (uint256) {
        return _length(_list);
    }

    /** @dev Returns the address at the head of the `_list`.
     *  @param _list The list to get the head.
     *  @return The address.
     */
    function getHead(List storage _list) internal view returns (address) {
        return _list.head;
    }

    /** @dev Returns the address at the tail of the `_list`.
     *  @param _list The list to get the tail.
     *  @return The address.
     */
    function getTail(List storage _list) internal view returns (address) {
        return _list.tail;
    }

    /** @dev Sets the head of the `_list`.
     *  @param _list The list to set the head.
     */
    function _setHead(List storage _list, address _id) private {
        _list.head = _id;
    }

    /** @dev Sets the tail of the `_list`.
     *  @param _list The list to set the tail.
     */
    function _setTail(List storage _list, address _id) private {
        _list.tail = _id;
    }

    /** @dev Creates an account based on its `_id` and `_value`.
     *  @param _list The list to set the tail.
     *  @param _id The address of the account.
     *  @param _value The value of the account.
     */
    function _createAccount(
        List storage _list,
        address _id,
        uint256 _value
    ) private {
        _list.counter += 1;
        Account memory account = Account(_id, address(0), address(0), _value, true);
        _list.accounts[_id] = account;
    }

    /** @dev Links an account to its previous and next accounts.
     *  @param _list The list to set the tail.
     *  @param _prevId The address of the previous account.
     *  @param _nextId The address of the next account.
     */
    function _link(
        List storage _list,
        address _prevId,
        address _nextId
    ) private {
        _list.accounts[_prevId].next = _nextId;
        _list.accounts[_nextId].prev = _prevId;
    }

    /** @dev Returns whether or not the account is in the `_list`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return whether or not the account is in the `_list`.
     */
    function _contains(List storage _list, address _id) private view returns (bool) {
        return _list.accounts[_id].isIn;
    }

    /** @dev Returns the length of the `_list`.
     *  @param _list The list to get the length.
     *  @return The length.
     */
    function _length(List storage _list) private view returns (uint256) {
        return _list.counter;
    }
}
