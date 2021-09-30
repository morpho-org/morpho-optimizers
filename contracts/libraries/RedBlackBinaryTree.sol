// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

/*
A Solidity Red-Black Tree library to store and maintain a sorted data
structure in a Red-Black binary search tree, with O(log 2n) insert, remove
and search time (and gas, approximately) based on
https://github.com/rob-Hitchens/OrderStatisticsTree
Copyright (c) Rob Hitchens. the MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
Significant portions from BokkyPooBahsRedBlackTreeLibrary,
https://github.com/bokkypoobah/BokkyPooBahsRedBlackTreeLibrary
THIS SOFTWARE IS NOT TESTED OR AUDITED. DO NOT USE FOR PRODUCTION.
*/

library RedBlackBinaryTree {
    struct Node {
        uint256 parent;
        uint256 left;
        uint256 right;
        bool red;
        address[] keys;
        mapping(address => uint256) keyMap;
        uint256 count;
    }

    struct Tree {
        uint256 root;
        mapping(uint256 => Node) nodes;
        mapping(address => uint256) keyToValue;
        mapping(address => bool) isIn;
    }

    function first(Tree storage self) public view returns (uint256 _value) {
        _value = self.root;
        if (_value == 0) return 0;
        while (self.nodes[_value].left != 0) {
            _value = self.nodes[_value].left;
        }
    }

    function last(Tree storage self) public view returns (uint256 _value) {
        _value = self.root;
        if (_value == 0) return 0;
        while (self.nodes[_value].right != 0) {
            _value = self.nodes[_value].right;
        }
    }

    function next(Tree storage self, uint256 value) public view returns (uint256 _cursor) {
        require(value != 0, "RBBT(401):start-value=0");
        if (self.nodes[value].right != 0) {
            _cursor = treeMinimum(self, self.nodes[value].right);
        } else {
            _cursor = self.nodes[value].parent;
            while (_cursor != 0 && value == self.nodes[_cursor].right) {
                value = _cursor;
                _cursor = self.nodes[_cursor].parent;
            }
        }
    }

    function prev(Tree storage self, uint256 value) public view returns (uint256 _cursor) {
        require(value != 0, "RBBT(402):start-value=0");
        if (self.nodes[value].left != 0) {
            _cursor = treeMaximum(self, self.nodes[value].left);
        } else {
            _cursor = self.nodes[value].parent;
            while (_cursor != 0 && value == self.nodes[_cursor].left) {
                value = _cursor;
                _cursor = self.nodes[_cursor].parent;
            }
        }
    }

    function exists(Tree storage self, uint256 value) public view returns (bool) {
        if (value == 0) return false;
        if (value == self.root) return true;
        if (self.nodes[value].parent != 0) return true;
        return false;
    }

    function keyExists(Tree storage self, address key) public view returns (bool) {
        return self.isIn[key];
    }

    function getNodeCount(Tree storage self, uint256 value) public view returns (uint256) {
        Node storage gn = self.nodes[value];
        return gn.keys.length + gn.count;
    }

    function valueKeyAtIndex(
        Tree storage self,
        uint256 value,
        uint256 index
    ) public view returns (address _key) {
        require(exists(self, value), "RBBT(404):value-not-exist");
        return self.nodes[value].keys[index];
    }

    function count(Tree storage self) public view returns (uint256 _count) {
        return getNodeCount(self, self.root);
    }

    function insert(
        Tree storage self,
        address key,
        uint256 value
    ) public {
        require(value != 0, "RBBT(405):value-cannot-be-0");
        require(!self.isIn[key], "RBBT:account-already-in");
        self.isIn[key] = true;
        self.keyToValue[key] = value;
        uint256 cursor;
        uint256 probe = self.root;
        while (probe != 0) {
            cursor = probe;
            if (value < probe) {
                probe = self.nodes[probe].left;
            } else if (value > probe) {
                probe = self.nodes[probe].right;
            } else if (value == probe) {
                self.nodes[probe].keys.push(key);
                self.nodes[probe].keyMap[key] = self.nodes[probe].keys.length - 1;
                return;
            }
            self.nodes[cursor].count++;
        }
        Node storage nValue = self.nodes[value];
        nValue.parent = cursor;
        nValue.left = 0;
        nValue.right = 0;
        nValue.red = true;
        nValue.keys.push(key);
        nValue.keyMap[key] = nValue.keys.length - 1;
        if (cursor == 0) {
            self.root = value;
        } else if (value < cursor) {
            self.nodes[cursor].left = value;
        } else {
            self.nodes[cursor].right = value;
        }
        insertFixup(self, value);
    }

    function remove(Tree storage self, address key) public {
        require(self.isIn[key], "RBBT:account-not-exist");
        self.isIn[key] = false;
        uint256 value = self.keyToValue[key];
        Node storage nValue = self.nodes[value];
        uint256 rowToDelete = nValue.keyMap[key];
        nValue.keys[rowToDelete] = nValue.keys[nValue.keys.length - 1];
        nValue.keyMap[key] = rowToDelete;
        nValue.keys.pop();
        uint256 probe;
        uint256 cursor;
        if (nValue.keys.length == 0) {
            if (self.nodes[value].left == 0 || self.nodes[value].right == 0) {
                cursor = value;
            } else {
                cursor = self.nodes[value].right;
                while (self.nodes[cursor].left != 0) {
                    cursor = self.nodes[cursor].left;
                }
            }
            if (self.nodes[cursor].left != 0) {
                probe = self.nodes[cursor].left;
            } else {
                probe = self.nodes[cursor].right;
            }
            uint256 cursorParent = self.nodes[cursor].parent;
            self.nodes[probe].parent = cursorParent;
            if (cursorParent != 0) {
                if (cursor == self.nodes[cursorParent].left) {
                    self.nodes[cursorParent].left = probe;
                } else {
                    self.nodes[cursorParent].right = probe;
                }
            } else {
                self.root = probe;
            }
            bool doFixup = !self.nodes[cursor].red;
            if (cursor != value) {
                replaceParent(self, cursor, value);
                self.nodes[cursor].left = self.nodes[value].left;
                self.nodes[self.nodes[cursor].left].parent = cursor;
                self.nodes[cursor].right = self.nodes[value].right;
                self.nodes[self.nodes[cursor].right].parent = cursor;
                self.nodes[cursor].red = self.nodes[value].red;
                (cursor, value) = (value, cursor);
                fixCountRecurse(self, value);
            }
            if (doFixup) {
                removeFixup(self, probe);
            }
            fixCountRecurse(self, cursorParent);
            delete self.nodes[cursor];
        }
    }

    function fixCountRecurse(Tree storage self, uint256 value) private {
        while (value != 0) {
            self.nodes[value].count =
                getNodeCount(self, self.nodes[value].left) +
                getNodeCount(self, self.nodes[value].right);
            value = self.nodes[value].parent;
        }
    }

    function treeMinimum(Tree storage self, uint256 value) private view returns (uint256) {
        while (self.nodes[value].left != 0) {
            value = self.nodes[value].left;
        }
        return value;
    }

    function treeMaximum(Tree storage self, uint256 value) private view returns (uint256) {
        while (self.nodes[value].right != 0) {
            value = self.nodes[value].right;
        }
        return value;
    }

    function rotateLeft(Tree storage self, uint256 value) private {
        uint256 cursor = self.nodes[value].right;
        uint256 parent = self.nodes[value].parent;
        uint256 cursorLeft = self.nodes[cursor].left;
        self.nodes[value].right = cursorLeft;
        if (cursorLeft != 0) {
            self.nodes[cursorLeft].parent = value;
        }
        self.nodes[cursor].parent = parent;
        if (parent == 0) {
            self.root = cursor;
        } else if (value == self.nodes[parent].left) {
            self.nodes[parent].left = cursor;
        } else {
            self.nodes[parent].right = cursor;
        }
        self.nodes[cursor].left = value;
        self.nodes[value].parent = cursor;
        self.nodes[value].count =
            getNodeCount(self, self.nodes[value].left) +
            getNodeCount(self, self.nodes[value].right);
        self.nodes[cursor].count =
            getNodeCount(self, self.nodes[cursor].left) +
            getNodeCount(self, self.nodes[cursor].right);
    }

    function rotateRight(Tree storage self, uint256 value) private {
        uint256 cursor = self.nodes[value].left;
        uint256 parent = self.nodes[value].parent;
        uint256 cursorRight = self.nodes[cursor].right;
        self.nodes[value].left = cursorRight;
        if (cursorRight != 0) {
            self.nodes[cursorRight].parent = value;
        }
        self.nodes[cursor].parent = parent;
        if (parent == 0) {
            self.root = cursor;
        } else if (value == self.nodes[parent].right) {
            self.nodes[parent].right = cursor;
        } else {
            self.nodes[parent].left = cursor;
        }
        self.nodes[cursor].right = value;
        self.nodes[value].parent = cursor;
        self.nodes[value].count =
            getNodeCount(self, self.nodes[value].left) +
            getNodeCount(self, self.nodes[value].right);
        self.nodes[cursor].count =
            getNodeCount(self, self.nodes[cursor].left) +
            getNodeCount(self, self.nodes[cursor].right);
    }

    function insertFixup(Tree storage self, uint256 value) private {
        uint256 cursor;
        while (value != self.root && self.nodes[self.nodes[value].parent].red) {
            uint256 valueParent = self.nodes[value].parent;
            if (valueParent == self.nodes[self.nodes[valueParent].parent].left) {
                cursor = self.nodes[self.nodes[valueParent].parent].right;
                if (self.nodes[cursor].red) {
                    self.nodes[valueParent].red = false;
                    self.nodes[cursor].red = false;
                    self.nodes[self.nodes[valueParent].parent].red = true;
                    value = self.nodes[valueParent].parent;
                } else {
                    if (value == self.nodes[valueParent].right) {
                        value = valueParent;
                        rotateLeft(self, value);
                    }
                    valueParent = self.nodes[value].parent;
                    self.nodes[valueParent].red = false;
                    self.nodes[self.nodes[valueParent].parent].red = true;
                    rotateRight(self, self.nodes[valueParent].parent);
                }
            } else {
                cursor = self.nodes[self.nodes[valueParent].parent].left;
                if (self.nodes[cursor].red) {
                    self.nodes[valueParent].red = false;
                    self.nodes[cursor].red = false;
                    self.nodes[self.nodes[valueParent].parent].red = true;
                    value = self.nodes[valueParent].parent;
                } else {
                    if (value == self.nodes[valueParent].left) {
                        value = valueParent;
                        rotateRight(self, value);
                    }
                    valueParent = self.nodes[value].parent;
                    self.nodes[valueParent].red = false;
                    self.nodes[self.nodes[valueParent].parent].red = true;
                    rotateLeft(self, self.nodes[valueParent].parent);
                }
            }
        }
        self.nodes[self.root].red = false;
    }

    function replaceParent(
        Tree storage self,
        uint256 a,
        uint256 b
    ) private {
        uint256 bParent = self.nodes[b].parent;
        self.nodes[a].parent = bParent;
        if (bParent == 0) {
            self.root = a;
        } else {
            if (b == self.nodes[bParent].left) {
                self.nodes[bParent].left = a;
            } else {
                self.nodes[bParent].right = a;
            }
        }
    }

    function removeFixup(Tree storage self, uint256 value) private {
        uint256 cursor;
        while (value != self.root && !self.nodes[value].red) {
            uint256 valueParent = self.nodes[value].parent;
            if (value == self.nodes[valueParent].left) {
                cursor = self.nodes[valueParent].right;
                if (self.nodes[cursor].red) {
                    self.nodes[cursor].red = false;
                    self.nodes[valueParent].red = true;
                    rotateLeft(self, valueParent);
                    cursor = self.nodes[valueParent].right;
                }
                if (
                    !self.nodes[self.nodes[cursor].left].red &&
                    !self.nodes[self.nodes[cursor].right].red
                ) {
                    self.nodes[cursor].red = true;
                    value = valueParent;
                } else {
                    if (!self.nodes[self.nodes[cursor].right].red) {
                        self.nodes[self.nodes[cursor].left].red = false;
                        self.nodes[cursor].red = true;
                        rotateRight(self, cursor);
                        cursor = self.nodes[valueParent].right;
                    }
                    self.nodes[cursor].red = self.nodes[valueParent].red;
                    self.nodes[valueParent].red = false;
                    self.nodes[self.nodes[cursor].right].red = false;
                    rotateLeft(self, valueParent);
                    value = self.root;
                }
            } else {
                cursor = self.nodes[valueParent].left;
                if (self.nodes[cursor].red) {
                    self.nodes[cursor].red = false;
                    self.nodes[valueParent].red = true;
                    rotateRight(self, valueParent);
                    cursor = self.nodes[valueParent].left;
                }
                if (
                    !self.nodes[self.nodes[cursor].right].red &&
                    !self.nodes[self.nodes[cursor].left].red
                ) {
                    self.nodes[cursor].red = true;
                    value = valueParent;
                } else {
                    if (!self.nodes[self.nodes[cursor].left].red) {
                        self.nodes[self.nodes[cursor].right].red = false;
                        self.nodes[cursor].red = true;
                        rotateLeft(self, cursor);
                        cursor = self.nodes[valueParent].left;
                    }
                    self.nodes[cursor].red = self.nodes[valueParent].red;
                    self.nodes[valueParent].red = false;
                    self.nodes[self.nodes[cursor].left].red = false;
                    rotateRight(self, valueParent);
                    value = self.root;
                }
            }
        }
        self.nodes[value].red = false;
    }
}
