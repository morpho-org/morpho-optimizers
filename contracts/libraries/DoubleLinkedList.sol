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

    function get(List storage _list, address _id) internal view returns (Account memory account) {
        return _list.accounts[_id];
    }

    function getNext(List storage _list, address _id) internal view returns (address) {
        return _list.accounts[_id].next;
    }

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

    function insertSorted(
        List storage _list,
        address _id,
        uint256 _value
    ) internal {
        require(!_contains(_list, _id));
        address previous = _list.head;
        while (previous != _list.tail && _list.accounts[previous].value >= _value) {
            previous = _list.accounts[previous].next;
        }
        insertBefore(_list, previous, _id, _value);
    }

    function insertBefore(
        List storage _list,
        address _nextId,
        address _id,
        uint256 _value
    ) internal {
        require(!_contains(_list, _id));
        if (_nextId == _list.head) addHead(_list, _id, _value);
        else insertAfter(_list, _list.accounts[_nextId].prev, _id, _value);
    }

    function insertAfter(
        List storage _list,
        address _prevId,
        address _id,
        uint256 _value
    ) internal returns (bool) {
        require(!_contains(_list, _id));
        if (_prevId == _list.tail) {
            return addTail(_list, _id, _value);
        } else {
            Account memory prevAccount = _list.accounts[_prevId];
            Account memory nextAccount = _list.accounts[prevAccount.next];
            _createAccount(_list, _id, _value);
            _link(_list, _id, nextAccount.id);
            _link(_list, prevAccount.id, _id);
            return true;
        }
    }

    function contains(List storage _list, address _id) internal view returns (bool) {
        return _contains(_list, _id);
    }

    function length(List storage _list) internal view returns (uint256) {
        return _length(_list);
    }

    function getHead(List storage _list) internal view returns (address) {
        return _list.head;
    }

    function getTail(List storage _list) internal view returns (address) {
        return _list.tail;
    }

    function _setHead(List storage _list, address _id) private {
        _list.head = _id;
    }

    function _setTail(List storage _list, address _id) private {
        _list.tail = _id;
    }

    function _createAccount(
        List storage _list,
        address _id,
        uint256 _value
    ) private {
        _list.counter += 1;
        Account memory account = Account(_id, address(0), address(0), _value, true);
        _list.accounts[_id] = account;
    }

    function _link(
        List storage _list,
        address _prevId,
        address _nextId
    ) private {
        _list.accounts[_prevId].next = _nextId;
        _list.accounts[_nextId].prev = _prevId;
    }

    function _contains(List storage _list, address _id) private view returns (bool) {
        return _list.accounts[_id].isIn;
    }

    function _length(List storage _list) private view returns (uint256) {
        return _list.counter;
    }
}
