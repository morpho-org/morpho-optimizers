// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

// A Solidity Red-Black Tree library to store and maintain a sorted data structure in a Red-Black binary search tree,
// with O(log 2n) insert, remove and search time (and gas, approximately) based on https://github.com/rob-Hitchens/OrderStatisticsTree
// Copyright (c) Rob Hitchens. the MIT License.
// Significant portions from BokkyPooBahsRedBlackTreeLibrary,
// https://github.com/bokkypoobah/BokkyPooBahsRedBlackTreeLibrary

library RedBlackBinaryTree {
    struct Node {
        address parent; // The parent node of the current node.
        address leftChild; // The left child of the current node.
        address rightChild; // The right child of the current node.
        bool red; // Whether the current node is red or black.
    }

    struct Tree {
        address root; // address of the root node
        mapping(address => Node) nodes; // Map user's address to node
        mapping(address => uint256) keyToValue; // Maps key to its value
    }

    /** @dev Returns the address of the smallest value in the tree `_self`.
     *  @param _self The tree to search in.
     */
    function first(Tree storage _self) public view returns (address key) {
        key = _self.root;
        if (key == address(0)) return address(0);
        while (_self.nodes[key].leftChild != address(0)) {
            key = _self.nodes[key].leftChild;
        }
    }

    /** @dev Returns the address of the highest value in the tree `_self`.
     *  @param _self The tree to search in.
     */
    function last(Tree storage _self) public view returns (address key) {
        key = _self.root;
        if (key == address(0)) return address(0);
        while (_self.nodes[key].rightChild != address(0)) {
            key = _self.nodes[key].rightChild;
        }
    }

    /** @dev Returns the address of the next user after `_key`.
     *  @param _self The tree to search in.
     *  @param _key The address to search after.
     */
    function next(Tree storage _self, address _key) public view returns (address cursor) {
        require(_key != address(0), "RBBT(1):key-is-nul-address");
        if (_self.nodes[_key].rightChild != address(0)) {
            cursor = subTreeMin(_self, _self.nodes[_key].rightChild);
        } else {
            cursor = _self.nodes[_key].parent;
            while (cursor != address(0) && _key == _self.nodes[cursor].rightChild) {
                _key = cursor;
                cursor = _self.nodes[cursor].parent;
            }
        }
    }

    /** @dev Returns the address of the previous user above `_key`.
     *  @param _self The tree to search in.
     *  @param _key The address to search before.
     */
    function prev(Tree storage _self, address _key) public view returns (address cursor) {
        require(_key != address(0), "RBBT(2):start-value=0");
        if (_self.nodes[_key].leftChild != address(0)) {
            cursor = subTreeMax(_self, _self.nodes[_key].leftChild);
        } else {
            cursor = _self.nodes[_key].parent;
            while (cursor != address(0) && _key == _self.nodes[cursor].leftChild) {
                _key = cursor;
                cursor = _self.nodes[cursor].parent;
            }
        }
    }

    /** @dev Returns whether the `_key` exists in the tree or not.
     *  @param _self The tree to search in.
     *  @param _key The key to search.
     *  @return Whether the `_key` exists in the tree or not.
     */
    function keyExists(Tree storage _self, address _key) public view returns (bool) {
        return _self.keyToValue[_key] != 0;
    }

    /** @dev Returns true if A>B according to the order relationship.
     *  @param _valueA value for user A.
     *  @param _addressA Address for user A.
     *  @param _valueB value for user B.
     *  @param _addressB Address for user B.
     */
    function compare(
        uint256 _valueA,
        address _addressA,
        uint256 _valueB,
        address _addressB
    ) public pure returns (bool) {
        if (_valueA == _valueB) {
            if (_addressA > _addressB) {
                return true;
            }
        }
        if (_valueA > _valueB) {
            return true;
        }
        return false;
    }

    /** @dev Returns whether or not there is any key in the tree.
     *  @param _self The tree to search in.
     *  @return Whether or not a key exist in the tree.
     */
    function isNotEmpty(Tree storage _self) public view returns (bool) {
        return _self.root != address(0);
    }

    /** @dev Inserts the `_key` with `_value` in the tree.
     *  @param _self The tree in which to add the (key, value) pair.
     *  @param _key The key to add.
     *  @param _value The value to add.
     */
    function insert(
        Tree storage _self,
        address _key,
        uint256 _value
    ) public {
        require(_value != 0, "RBBT:value-cannot-be-0");
        require(_self.keyToValue[_key] == 0, "RBBT:account-already-in");
        _self.keyToValue[_key] = _value;
        address cursor;
        address probe = _self.root;
        while (probe != address(0)) {
            cursor = probe;
            if (compare(_self.keyToValue[probe], probe, _value, _key)) {
                probe = _self.nodes[probe].leftChild;
            } else {
                probe = _self.nodes[probe].rightChild;
            }
        }
        Node storage nValue = _self.nodes[_key];
        nValue.parent = cursor;
        nValue.leftChild = address(0);
        nValue.rightChild = address(0);
        nValue.red = true;
        if (cursor == address(0)) {
            _self.root = _key;
        } else if (compare(_self.keyToValue[cursor], cursor, _value, _key)) {
            _self.nodes[cursor].leftChild = _key;
        } else {
            _self.nodes[cursor].rightChild = _key;
        }
        insertFixup(_self, _key);
    }

    /** @dev Removes the `_key` in the tree and its related value if no-one shares the same value.
     *  @param _self The tree in which to remove the (key, value) pair.
     *  @param _key The key to remove.
     */
    function remove(Tree storage _self, address _key) public {
        require(_self.keyToValue[_key] != 0, "RBBT:account-not-exist");
        _self.keyToValue[_key] = 0;
        address probe;
        address cursor;
        if (
            _self.nodes[_key].leftChild == address(0) || _self.nodes[_key].rightChild == address(0)
        ) {
            cursor = _key;
        } else {
            cursor = _self.nodes[_key].rightChild;
            while (_self.nodes[cursor].leftChild != address(0)) {
                cursor = _self.nodes[cursor].leftChild;
            }
        }
        if (_self.nodes[cursor].leftChild != address(0)) {
            probe = _self.nodes[cursor].leftChild;
        } else {
            probe = _self.nodes[cursor].rightChild;
        }
        address cursorParent = _self.nodes[cursor].parent;
        _self.nodes[probe].parent = cursorParent;
        if (cursorParent != address(0)) {
            if (cursor == _self.nodes[cursorParent].leftChild) {
                _self.nodes[cursorParent].leftChild = probe;
            } else {
                _self.nodes[cursorParent].rightChild = probe;
            }
        } else {
            _self.root = probe;
        }
        bool doFixup = !_self.nodes[cursor].red;
        if (cursor != _key) {
            replaceParent(_self, cursor, _key);
            _self.nodes[cursor].leftChild = _self.nodes[_key].leftChild;
            _self.nodes[_self.nodes[cursor].leftChild].parent = cursor;
            _self.nodes[cursor].rightChild = _self.nodes[_key].rightChild;
            _self.nodes[_self.nodes[cursor].rightChild].parent = cursor;
            _self.nodes[cursor].red = _self.nodes[_key].red;
            (cursor, _key) = (_key, cursor);
        }
        if (doFixup) {
            removeFixup(_self, probe);
        }
        delete _self.nodes[cursor];
    }

    /** @dev Returns the minimum of the subtree beginning at a given node.
     *  @param _self The tree to search in.
     *  @param _key The value of the node to start at.
     */
    function subTreeMin(Tree storage _self, address _key) private view returns (address) {
        while (_self.nodes[_key].leftChild != address(0)) {
            _key = _self.nodes[_key].leftChild;
        }
        return _key;
    }

    /** @dev Returns the maximum of the subtree beginning at a given node.
     *  @param _self The tree to search in.
     *  @param _key The address of the node to start at.
     */
    function subTreeMax(Tree storage _self, address _key) private view returns (address) {
        while (_self.nodes[_key].rightChild != address(0)) {
            _key = _self.nodes[_key].rightChild;
        }
        return _key;
    }

    /** @dev Rotates the tree to keep the balance. Let's have three node, A (root), B (A's rightChild child), C (B's leftChild child).
     *       After leftChild rotation: B (Root), A (B's leftChild child), C (B's rightChild child)
     *  @param _self The tree to apply the rotation to.
     *  @param _key The address of the node to rotate.
     */
    function rotateLeft(Tree storage _self, address _key) private {
        address cursor = _self.nodes[_key].rightChild;
        address parent = _self.nodes[_key].parent;
        address cursorLeft = _self.nodes[cursor].leftChild;
        _self.nodes[_key].rightChild = cursorLeft;

        if (cursorLeft != address(0)) {
            _self.nodes[cursorLeft].parent = _key;
        }
        _self.nodes[cursor].parent = parent;
        if (parent == address(0)) {
            _self.root = cursor;
        } else if (_key == _self.nodes[parent].leftChild) {
            _self.nodes[parent].leftChild = cursor;
        } else {
            _self.nodes[parent].rightChild = cursor;
        }
        _self.nodes[cursor].leftChild = _key;
        _self.nodes[_key].parent = cursor;
    }

    /** @dev Rotates the tree to keep the balance. Let's have three node, A (root), B (A's leftChild child), C (B's rightChild child).
             After rightChild rotation: B (Root), A (B's rightChild child), C (B's leftChild child)
     *  @param _self The tree to apply the rotation to.
     *  @param _key The address of the node to rotate.
     */
    function rotateRight(Tree storage _self, address _key) private {
        address cursor = _self.nodes[_key].leftChild;
        address parent = _self.nodes[_key].parent;
        address cursorRight = _self.nodes[cursor].rightChild;
        _self.nodes[_key].leftChild = cursorRight;
        if (cursorRight != address(0)) {
            _self.nodes[cursorRight].parent = _key;
        }
        _self.nodes[cursor].parent = parent;
        if (parent == address(0)) {
            _self.root = cursor;
        } else if (_key == _self.nodes[parent].rightChild) {
            _self.nodes[parent].rightChild = cursor;
        } else {
            _self.nodes[parent].leftChild = cursor;
        }
        _self.nodes[cursor].rightChild = _key;
        _self.nodes[_key].parent = cursor;
    }

    /** @dev Makes sure there is no violation of the tree properties after an insertion.
     *  @param _self The tree to check and correct if needed.
     *  @param _key The address of the user that was inserted.
     */
    function insertFixup(Tree storage _self, address _key) private {
        address cursor;
        while (_key != _self.root && _self.nodes[_self.nodes[_key].parent].red) {
            address keyParent = _self.nodes[_key].parent;
            if (keyParent == _self.nodes[_self.nodes[keyParent].parent].leftChild) {
                cursor = _self.nodes[_self.nodes[keyParent].parent].rightChild;
                if (_self.nodes[cursor].red) {
                    _self.nodes[keyParent].red = false;
                    _self.nodes[cursor].red = false;
                    _self.nodes[_self.nodes[keyParent].parent].red = true;
                    _key = keyParent;
                } else {
                    if (_key == _self.nodes[keyParent].rightChild) {
                        _key = keyParent;
                        rotateLeft(_self, _key);
                    }
                    keyParent = _self.nodes[_key].parent;
                    _self.nodes[keyParent].red = false;
                    _self.nodes[_self.nodes[keyParent].parent].red = true;
                    rotateRight(_self, _self.nodes[keyParent].parent);
                }
            } else {
                cursor = _self.nodes[_self.nodes[keyParent].parent].leftChild;
                if (_self.nodes[cursor].red) {
                    _self.nodes[keyParent].red = false;
                    _self.nodes[cursor].red = false;
                    _self.nodes[_self.nodes[keyParent].parent].red = true;
                    _key = _self.nodes[keyParent].parent;
                } else {
                    if (_key == _self.nodes[keyParent].leftChild) {
                        _key = keyParent;
                        rotateRight(_self, _key);
                    }
                    keyParent = _self.nodes[_key].parent;
                    _self.nodes[keyParent].red = false;
                    _self.nodes[_self.nodes[keyParent].parent].red = true;
                    rotateLeft(_self, _self.nodes[keyParent].parent);
                }
            }
        }
        _self.nodes[_self.root].red = false;
    }

    /** @dev Replace the parent of A by B's parent.
     *  @param _self The tree to work with.
     *  @param _a The node that will get the new parents.
     *  @param _b The node that gives its parent.
     */
    function replaceParent(
        Tree storage _self,
        address _a,
        address _b
    ) private {
        address bParent = _self.nodes[_b].parent;
        _self.nodes[_a].parent = bParent;
        if (bParent == address(0)) {
            _self.root = _a;
        } else {
            if (_b == _self.nodes[bParent].leftChild) {
                _self.nodes[bParent].leftChild = _a;
            } else {
                _self.nodes[bParent].rightChild = _a;
            }
        }
    }

    /** @dev Makes sure there is no violation of the tree properties after removal.
     *  @param _self The tree to check and correct if needed.
     *  @param _key The address requested in the function remove.
     */
    function removeFixup(Tree storage _self, address _key) private {
        address cursor;
        while (_key != _self.root && !_self.nodes[_key].red) {
            address keyParent = _self.nodes[_key].parent;
            if (_key == _self.nodes[keyParent].leftChild) {
                cursor = _self.nodes[keyParent].rightChild;
                if (_self.nodes[cursor].red) {
                    _self.nodes[cursor].red = false;
                    _self.nodes[keyParent].red = true;
                    rotateLeft(_self, keyParent);
                    cursor = _self.nodes[keyParent].rightChild;
                }
                if (
                    !_self.nodes[_self.nodes[cursor].leftChild].red &&
                    !_self.nodes[_self.nodes[cursor].rightChild].red
                ) {
                    _self.nodes[cursor].red = true;
                    _key = keyParent;
                } else {
                    if (!_self.nodes[_self.nodes[cursor].rightChild].red) {
                        _self.nodes[_self.nodes[cursor].leftChild].red = false;
                        _self.nodes[cursor].red = true;
                        rotateRight(_self, cursor);
                        cursor = _self.nodes[keyParent].rightChild;
                    }
                    _self.nodes[cursor].red = _self.nodes[keyParent].red;
                    _self.nodes[keyParent].red = false;
                    _self.nodes[_self.nodes[cursor].rightChild].red = false;
                    rotateLeft(_self, keyParent);
                    _key = _self.root;
                }
            } else {
                cursor = _self.nodes[keyParent].leftChild;
                if (_self.nodes[cursor].red) {
                    _self.nodes[cursor].red = false;
                    _self.nodes[keyParent].red = true;
                    rotateRight(_self, keyParent);
                    cursor = _self.nodes[keyParent].leftChild;
                }
                if (
                    !_self.nodes[_self.nodes[cursor].rightChild].red &&
                    !_self.nodes[_self.nodes[cursor].leftChild].red
                ) {
                    _self.nodes[cursor].red = true;
                    _key = keyParent;
                } else {
                    if (!_self.nodes[_self.nodes[cursor].leftChild].red) {
                        _self.nodes[_self.nodes[cursor].rightChild].red = false;
                        _self.nodes[cursor].red = true;
                        rotateLeft(_self, cursor);
                        cursor = _self.nodes[keyParent].leftChild;
                    }
                    _self.nodes[cursor].red = _self.nodes[keyParent].red;
                    _self.nodes[keyParent].red = false;
                    _self.nodes[_self.nodes[cursor].leftChild].red = false;
                    rotateRight(_self, keyParent);
                    _key = _self.root;
                }
            }
        }
        _self.nodes[_key].red = false;
    }
}
