// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

library DoubleLinkedList {
    struct Account {
        address add;
        address next;
        address prev;
        uint256 value;
        bool isIn;
    }

    struct List {
        mapping(address => Account) accounts;
        mapping(uint256 => address) slotToAddress;
        address head;
        address tail;
        uint256 counter;
    }

    function get(List storage _list, address _add) internal view returns (Account memory account) {
        return _list.accounts[_add];
    }

    function getNext(List storage _list, address _add) internal view returns (address) {
        return _list.accounts[_add].next;
    }

    function addHead(
        List storage _list,
        address _add,
        uint256 _value
    ) internal returns (bool) {
        if (!_contains(_list, _add)) {
            _createAccount(_list, _add, _value);
            _link(_list, _add, _list.head);
            _setHead(_list, _add);
            if (_list.tail == address(0)) _setTail(_list, _add);
            return true;
        } else {
            return false;
        }
    }

    function addTail(
        List storage _list,
        address _add,
        uint256 _value
    ) internal returns (bool) {
        if (!_contains(_list, _add)) {
            if (_list.head == address(0)) {
                addHead(_list, _add, _value);
            } else {
                _createAccount(_list, _add, _value);
                _link(_list, _list.tail, _add);
                _setTail(_list, _add);
            }
            return true;
        } else {
            return false;
        }
    }

    function remove(List storage _list, address _add) internal returns (bool) {
        if (_contains(_list, _add)) {
            Account memory account = _list.accounts[_add];
            if (_list.head == _add && _list.tail == _add) {
                _setHead(_list, address(0));
                _setTail(_list, address(0));
            } else if (_list.head == _add) {
                _setHead(_list, account.next);
                _list.accounts[account.next].prev = address(0);
            } else if (_list.tail == _add) {
                _setTail(_list, account.prev);
                _list.accounts[account.prev].next = address(0);
            } else {
                _link(_list, account.prev, account.next);
            }
            _list.counter -= 1;
            delete _list.accounts[account.add];
            return true;
        } else {
            return false;
        }
    }

    function insertSorted(
        List storage _list,
        address _add,
        uint256 _value
    ) internal {
        require(!_contains(_list, _add));
        address previous = _list.head;
        while (previous != _list.tail && _list.accounts[previous].value >= _value) {
            previous = _list.accounts[previous].next;
        }
        insertBefore(_list, previous, _add, _value);
    }

    function insertBefore(
        List storage _list,
        address _nextId,
        address _add,
        uint256 _value
    ) internal {
        require(!_contains(_list, _add));
        if (_nextId == _list.head) addHead(_list, _add, _value);
        else insertAfter(_list, _list.accounts[_nextId].prev, _add, _value);
    }

    function insertAfter(
        List storage _list,
        address _prevId,
        address _add,
        uint256 _value
    ) internal returns (bool) {
        require(!_contains(_list, _add));
        if (_prevId == _list.tail) {
            return addTail(_list, _add, _value);
        } else {
            Account memory prevAccount = _list.accounts[_prevId];
            Account memory nextAccount = _list.accounts[prevAccount.next];
            _createAccount(_list, _add, _value);
            _link(_list, _add, nextAccount.add);
            _link(_list, prevAccount.add, _add);
            return true;
        }
    }

    function contains(List storage _list, address _add) internal view returns (bool) {
        return _contains(_list, _add);
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

    function _setHead(List storage _list, address _add) private {
        _list.head = _add;
    }

    function _setTail(List storage _list, address _add) private {
        _list.tail = _add;
    }

    function _createAccount(
        List storage _list,
        address _add,
        uint256 _value
    ) private {
        _list.counter += 1;
        Account memory account = Account(_add, address(0), address(0), _value, true);
        _list.accounts[_add] = account;
    }

    function _link(
        List storage _list,
        address _prevId,
        address _nextId
    ) private {
        _list.accounts[_prevId].next = _nextId;
        _list.accounts[_nextId].prev = _prevId;
    }

    function _contains(List storage _list, address _add) private view returns (bool) {
        return _list.accounts[_add].isIn;
    }

    function _length(List storage _list) private view returns (uint256) {
        return _list.counter;
    }
}
