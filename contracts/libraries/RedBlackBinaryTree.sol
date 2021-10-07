// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

// A Solidity Red-Black Tree library to store and maintain a sorted data structure in a Red-Black binary search tree,
// with O(log 2n) insert, remove and search time (and gas, approximately) based on https://github.com/rob-Hitchens/OrderStatisticsTree
// Copyright (c) Rob Hitchens. the MIT License.
// Significant portions from BokkyPooBahsRedBlackTreeLibrary,
// https://github.com/bokkypoobah/BokkyPooBahsRedBlackTreeLibrary

library RedBlackBinaryTree {
    struct Node {
        uint256 parent;
        uint256 left;
        uint256 right;
        bool red;
        address[] keys;
        mapping(address => uint256) keyMap;
    }

    struct Tree {
        uint256 root;
        mapping(uint256 => Node) nodes;
        mapping(address => uint256) keyToValue;
    }

    /** @dev Returns the smallest value in the tree `_self`.
     *  @param _self The tree to search in.
     */
    function first(Tree storage _self) public view returns (uint256 value) {
        value = _self.root;
        if (value == 0) return 0;
        while (_self.nodes[value].left != 0) {
            value = _self.nodes[value].left;
        }
    }

    /** @dev Returns the highest value in the tree `_self`.
     *  @param _self The tree to search in.
     */
    function last(Tree storage _self) public view returns (uint256 value) {
        value = _self.root;
        if (value == 0) return 0;
        while (_self.nodes[value].right != 0) {
            value = _self.nodes[value].right;
        }
    }

    /** @dev Returns the next value below `_value`.
     *  @param _self The tree to search in.
     *  @param _value The value to search after.
     */
    function next(Tree storage _self, uint256 _value) public view returns (uint256 cursor) {
        require(_value != 0, "RBBT(401):start-_value=0");
        if (_self.nodes[_value].right != 0) {
            cursor = treeMinimum(_self, _self.nodes[_value].right);
        } else {
            cursor = _self.nodes[_value].parent;
            while (cursor != 0 && _value == _self.nodes[cursor].right) {
                _value = cursor;
                cursor = _self.nodes[cursor].parent;
            }
        }
    }

    /** @dev Returns the previous value above `_value`.
     *  @param _self The tree to search in.
     *  @param _value The value to search before.
     */
    function prev(Tree storage _self, uint256 _value) public view returns (uint256 cursor) {
        require(_value != 0, "RBBT(402):start-_value=0");
        if (_self.nodes[_value].left != 0) {
            cursor = treeMaximum(_self, _self.nodes[_value].left);
        } else {
            cursor = _self.nodes[_value].parent;
            while (cursor != 0 && _value == _self.nodes[cursor].left) {
                _value = cursor;
                cursor = _self.nodes[cursor].parent;
            }
        }
    }

    /** @dev Returns whether the `_value` exists in the tree or not.
     *  @param _self The tree to search in.
     *  @param _value The value to search.
     *  @return Whether the `_value` exists in the tree or not.
     */
    function exists(Tree storage _self, uint256 _value) public view returns (bool) {
        if (_value == 0) return false;
        if (_value == _self.root) return true;
        if (_self.nodes[_value].parent != 0) return true;
        return false;
    }

    /** @dev Returns whether the `_key` exists in the tree or not.
     *  @param _self The tree to search in.
     *  @param _key The key to search.
     *  @return Whether the `_key` exists in the tree or not.
     */
    function keyExists(Tree storage _self, address _key) public view returns (bool) {
        return _self.keyToValue[_key] != 0;
    }

    /** @dev Returns the `_key` that has the given `_value` at the specified `_index`.
     *  @param _self The tree to search in.
     *  @param _value The value to search.
     *  @param _index The index in the list of keys.
     *  @return The key address.
     */
    function valueKeyAtIndex(
        Tree storage _self,
        uint256 _value,
        uint256 _index
    ) public view returns (address) {
        require(exists(_self, _value), "RBBT(404):value-not-exist");
        return _self.nodes[_value].keys[_index];
    }

    /** @dev Returns the number of keys in a given node.
     *  @param _self The tree to search in.
     *  @param _value The value of the node to search for.
     *  @return The number of keys in this node.
     */
    function getNumberOfKeysAtValue(Tree storage _self, uint256 _value)
        public
        view
        returns (uint256)
    {
        if (!exists(_self, _value)) return 0;
        return _self.nodes[_value].keys.length;
    }

    /** @dev Returns whether or not there is any key in the tree.
     *  @param _self The tree to search in.
     *  @return Whether or not a key exist in the tree.
     */
    function isKeyInTree(Tree storage _self) public view returns (bool) {
        return _self.nodes[_self.root].keys.length > 0;
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
        require(_value != 0, "RBBT(405):value-cannot-be-0");
        require(_self.keyToValue[_key] == 0, "RBBT:account-already-in");
        _self.keyToValue[_key] = _value;
        uint256 cursor;
        uint256 probe = _self.root;
        while (probe != 0) {
            cursor = probe;
            if (_value < probe) {
                probe = _self.nodes[probe].left;
            } else if (_value > probe) {
                probe = _self.nodes[probe].right;
            } else if (_value == probe) {
                _self.nodes[probe].keys.push(_key);
                _self.nodes[probe].keyMap[_key] = _self.nodes[probe].keys.length - 1;
                return;
            }
        }
        Node storage nValue = _self.nodes[_value];
        nValue.parent = cursor;
        nValue.left = 0;
        nValue.right = 0;
        nValue.red = true;
        nValue.keys.push(_key);
        nValue.keyMap[_key] = nValue.keys.length - 1;
        if (cursor == 0) {
            _self.root = _value;
        } else if (_value < cursor) {
            _self.nodes[cursor].left = _value;
        } else {
            _self.nodes[cursor].right = _value;
        }
        insertFixup(_self, _value);
    }

    /** @dev Removes the `_key` in the tree and its related value if no-one shares the same value.
     *  @param _self The tree in which to remove the (key, value) pair.
     *  @param _key The key to remove.
     */
    function remove(Tree storage _self, address _key) public {
        require(_self.keyToValue[_key] != 0, "RBBT:account-not-exist");
        uint256 value = _self.keyToValue[_key];
        _self.keyToValue[_key] = 0;
        Node storage nValue = _self.nodes[value];
        uint256 rowToDelete = nValue.keyMap[_key];
        nValue.keys[rowToDelete] = nValue.keys[nValue.keys.length - 1];
        nValue.keys.pop();
        uint256 probe;
        uint256 cursor;
        if (nValue.keys.length == 0) {
            if (_self.nodes[value].left == 0 || _self.nodes[value].right == 0) {
                cursor = value;
            } else {
                cursor = _self.nodes[value].right;
                while (_self.nodes[cursor].left != 0) {
                    cursor = _self.nodes[cursor].left;
                }
            }
            if (_self.nodes[cursor].left != 0) {
                probe = _self.nodes[cursor].left;
            } else {
                probe = _self.nodes[cursor].right;
            }
            uint256 cursorParent = _self.nodes[cursor].parent;
            _self.nodes[probe].parent = cursorParent;
            if (cursorParent != 0) {
                if (cursor == _self.nodes[cursorParent].left) {
                    _self.nodes[cursorParent].left = probe;
                } else {
                    _self.nodes[cursorParent].right = probe;
                }
            } else {
                _self.root = probe;
            }
            bool doFixup = !_self.nodes[cursor].red;
            if (cursor != value) {
                replaceParent(_self, cursor, value);
                _self.nodes[cursor].left = _self.nodes[value].left;
                _self.nodes[_self.nodes[cursor].left].parent = cursor;
                _self.nodes[cursor].right = _self.nodes[value].right;
                _self.nodes[_self.nodes[cursor].right].parent = cursor;
                _self.nodes[cursor].red = _self.nodes[value].red;
                (cursor, value) = (value, cursor);
            }
            if (doFixup) {
                removeFixup(_self, probe);
            }
            delete _self.nodes[cursor];
        }
    }

    /** @dev Returns the minimum of the subtree beginning at a given node.
     *  @param _self The tree to search in.
     *  @param _value The value of the node to start at.
     */
    function treeMinimum(Tree storage _self, uint256 _value) private view returns (uint256) {
        while (_self.nodes[_value].left != 0) {
            _value = _self.nodes[_value].left;
        }
        return _value;
    }

    /** @dev Returns the maximum of the subtree beginning at a given node.
     *  @param _self The tree to search in.
     *  @param _value The value of the node to start at.
     */
    function treeMaximum(Tree storage _self, uint256 _value) private view returns (uint256) {
        while (_self.nodes[_value].right != 0) {
            _value = _self.nodes[_value].right;
        }
        return _value;
    }

    /** @dev Rotates the tree to keep the balance. Let's have three node, A (root), B (A's right child), C (B's left child).
             After left rotation: B (Root), A (B's left child), C (B's right child)
     *  @param _self The tree to apply the rotation to.
     *  @param _value The value of the node to rotate.
     */
    function rotateLeft(Tree storage _self, uint256 _value) private {
        uint256 cursor = _self.nodes[_value].right;
        uint256 parent = _self.nodes[_value].parent;
        uint256 cursorLeft = _self.nodes[cursor].left;
        _self.nodes[_value].right = cursorLeft;
        if (cursorLeft != 0) {
            _self.nodes[cursorLeft].parent = _value;
        }
        _self.nodes[cursor].parent = parent;
        if (parent == 0) {
            _self.root = cursor;
        } else if (_value == _self.nodes[parent].left) {
            _self.nodes[parent].left = cursor;
        } else {
            _self.nodes[parent].right = cursor;
        }
        _self.nodes[cursor].left = _value;
        _self.nodes[_value].parent = cursor;
    }

    /** @dev Rotates the tree to keep the balance. Let's have three node, A (root), B (A's left child), C (B's right child).
             After right rotation: B (Root), A (B's right child), C (B's left child)
     *  @param _self The tree to apply the rotation to.
     *  @param _value The value of the node to rotate.
     */
    function rotateRight(Tree storage _self, uint256 _value) private {
        uint256 cursor = _self.nodes[_value].left;
        uint256 parent = _self.nodes[_value].parent;
        uint256 cursorRight = _self.nodes[cursor].right;
        _self.nodes[_value].left = cursorRight;
        if (cursorRight != 0) {
            _self.nodes[cursorRight].parent = _value;
        }
        _self.nodes[cursor].parent = parent;
        if (parent == 0) {
            _self.root = cursor;
        } else if (_value == _self.nodes[parent].right) {
            _self.nodes[parent].right = cursor;
        } else {
            _self.nodes[parent].left = cursor;
        }
        _self.nodes[cursor].right = _value;
        _self.nodes[_value].parent = cursor;
    }

    /** @dev Makes sure there is no violation of the tree properties after an insertion.
     *  @param _self The tree to check and correct if needed.
     *  @param _value The value that was inserted.
     */
    function insertFixup(Tree storage _self, uint256 _value) private {
        uint256 cursor;
        while (_value != _self.root && _self.nodes[_self.nodes[_value].parent].red) {
            uint256 valueParent = _self.nodes[_value].parent;
            if (valueParent == _self.nodes[_self.nodes[valueParent].parent].left) {
                cursor = _self.nodes[_self.nodes[valueParent].parent].right;
                if (_self.nodes[cursor].red) {
                    _self.nodes[valueParent].red = false;
                    _self.nodes[cursor].red = false;
                    _self.nodes[_self.nodes[valueParent].parent].red = true;
                    _value = _self.nodes[valueParent].parent;
                } else {
                    if (_value == _self.nodes[valueParent].right) {
                        _value = valueParent;
                        rotateLeft(_self, _value);
                    }
                    valueParent = _self.nodes[_value].parent;
                    _self.nodes[valueParent].red = false;
                    _self.nodes[_self.nodes[valueParent].parent].red = true;
                    rotateRight(_self, _self.nodes[valueParent].parent);
                }
            } else {
                cursor = _self.nodes[_self.nodes[valueParent].parent].left;
                if (_self.nodes[cursor].red) {
                    _self.nodes[valueParent].red = false;
                    _self.nodes[cursor].red = false;
                    _self.nodes[_self.nodes[valueParent].parent].red = true;
                    _value = _self.nodes[valueParent].parent;
                } else {
                    if (_value == _self.nodes[valueParent].left) {
                        _value = valueParent;
                        rotateRight(_self, _value);
                    }
                    valueParent = _self.nodes[_value].parent;
                    _self.nodes[valueParent].red = false;
                    _self.nodes[_self.nodes[valueParent].parent].red = true;
                    rotateLeft(_self, _self.nodes[valueParent].parent);
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
        uint256 _a,
        uint256 _b
    ) private {
        uint256 bParent = _self.nodes[_b].parent;
        _self.nodes[_a].parent = bParent;
        if (bParent == 0) {
            _self.root = _a;
        } else {
            if (_b == _self.nodes[bParent].left) {
                _self.nodes[bParent].left = _a;
            } else {
                _self.nodes[bParent].right = _a;
            }
        }
    }

    /** @dev Makes sure there is no violation of the tree properties after removal.
     *  @param _self The tree to check and correct if needed.
     *  @param _value The probe value of the function remove.
     */
    function removeFixup(Tree storage _self, uint256 _value) private {
        uint256 cursor;
        while (_value != _self.root && !_self.nodes[_value].red) {
            uint256 valueParent = _self.nodes[_value].parent;
            if (_value == _self.nodes[valueParent].left) {
                cursor = _self.nodes[valueParent].right;
                if (_self.nodes[cursor].red) {
                    _self.nodes[cursor].red = false;
                    _self.nodes[valueParent].red = true;
                    rotateLeft(_self, valueParent);
                    cursor = _self.nodes[valueParent].right;
                }
                if (
                    !_self.nodes[_self.nodes[cursor].left].red &&
                    !_self.nodes[_self.nodes[cursor].right].red
                ) {
                    _self.nodes[cursor].red = true;
                    _value = valueParent;
                } else {
                    if (!_self.nodes[_self.nodes[cursor].right].red) {
                        _self.nodes[_self.nodes[cursor].left].red = false;
                        _self.nodes[cursor].red = true;
                        rotateRight(_self, cursor);
                        cursor = _self.nodes[valueParent].right;
                    }
                    _self.nodes[cursor].red = _self.nodes[valueParent].red;
                    _self.nodes[valueParent].red = false;
                    _self.nodes[_self.nodes[cursor].right].red = false;
                    rotateLeft(_self, valueParent);
                    _value = _self.root;
                }
            } else {
                cursor = _self.nodes[valueParent].left;
                if (_self.nodes[cursor].red) {
                    _self.nodes[cursor].red = false;
                    _self.nodes[valueParent].red = true;
                    rotateRight(_self, valueParent);
                    cursor = _self.nodes[valueParent].left;
                }
                if (
                    !_self.nodes[_self.nodes[cursor].right].red &&
                    !_self.nodes[_self.nodes[cursor].left].red
                ) {
                    _self.nodes[cursor].red = true;
                    _value = valueParent;
                } else {
                    if (!_self.nodes[_self.nodes[cursor].left].red) {
                        _self.nodes[_self.nodes[cursor].right].red = false;
                        _self.nodes[cursor].red = true;
                        rotateLeft(_self, cursor);
                        cursor = _self.nodes[valueParent].left;
                    }
                    _self.nodes[cursor].red = _self.nodes[valueParent].red;
                    _self.nodes[valueParent].red = false;
                    _self.nodes[_self.nodes[cursor].left].red = false;
                    rotateRight(_self, valueParent);
                    _value = _self.root;
                }
            }
        }
        _self.nodes[_value].red = false;
    }
}
