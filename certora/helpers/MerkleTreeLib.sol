// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

library MerkleTreeLib {
    using MerkleTreeLib for Node;

    struct Node {
        address left;
        address right;
        uint256 value;
        bytes32 hashNode;
    }

    function isEmpty(Node memory node) internal pure returns (bool) {
        return
            node.left == address(0) &&
            node.right == address(0) &&
            node.value == 0 &&
            node.hashNode == bytes32(0);
    }

    struct Tree {
        mapping(address => Node) nodes;
        address root;
    }

    function newLeaf(
        Tree storage tree,
        address addr,
        uint256 value
    ) internal {
        Node storage node = tree.nodes[addr];
        require(addr != address(0), "addr is zero address");
        require(node.isEmpty(), "leaf is not empty");
        require(value != 0, "value is zero");

        node.value = value;
        node.hashNode = keccak256(abi.encodePacked(addr, value));
        require(node.hashNode << 160 != 0, "invalid leaf hash");
    }

    function newInternalNode(
        Tree storage tree,
        address parent,
        address left,
        address right
    ) internal {
        Node storage parentNode = tree.nodes[parent];
        Node storage leftNode = tree.nodes[left];
        Node storage rightNode = tree.nodes[right];
        require(parent != address(0), "parent is zero address");
        require(parentNode.isEmpty(), "parent is not empty");
        require(!leftNode.isEmpty(), "left is empty");
        require(!rightNode.isEmpty(), "right is empty");
        require(leftNode.hashNode <= rightNode.hashNode, "children are not pair sorted");

        parentNode.left = left;
        parentNode.right = right;
        // The value of an internal node represents the sum of the values of the leaves underneath.
        parentNode.value = leftNode.value + rightNode.value;
        parentNode.hashNode = keccak256(abi.encode(leftNode.hashNode, rightNode.hashNode));
        require(parentNode.hashNode << 160 != 0, "invalid node hash");
    }

    function setRoot(Tree storage tree, address addr) internal {
        require(!tree.nodes[addr].isEmpty(), "root is empty");
        tree.root = addr;
    }

    // The specification of a well-formed tree is the following:
    //   - empty nodes are well-formed
    //   - other nodes should have non-zero value, where the leaf node contains the value of the account and internal nodes contain the sum of the values of its leaf children.
    //   - correct hashing of leaves and of internal nodes
    //   - internal nodes have their children pair sorted and not empty
    function isWellFormed(Tree storage tree, address addr) internal view returns (bool) {
        Node storage node = tree.nodes[addr];

        if (node.isEmpty()) return true;

        // Trick to make the verification discriminate between internal nodes and leaves.
        // Safe because it will prompt a revert if this condition is not respected.
        if (node.hashNode << 160 == 0) return false;

        if (node.value == 0) return false;

        if (node.left == address(0) && node.right == address(0)) {
            return node.hashNode == keccak256(abi.encodePacked(addr, node.value));
        } else {
            // Well-formed nodes have exactly 0 or 2 children.
            if (node.left == address(0) || node.right == address(0)) return false;
            Node storage left = tree.nodes[node.left];
            Node storage right = tree.nodes[node.right];
            // Well-formed nodes should have its children pair-sorted.
            bool sorted = left.hashNode <= right.hashNode;
            return
                !left.isEmpty() &&
                !right.isEmpty() &&
                sorted &&
                node.hashNode == keccak256(abi.encode(left.hashNode, right.hashNode));
        }
    }

    function isEmpty(Tree storage tree, address addr) internal view returns (bool) {
        return tree.nodes[addr].isEmpty();
    }

    function getRoot(Tree storage tree) internal view returns (address) {
        return tree.root;
    }

    function getLeft(Tree storage tree, address addr) internal view returns (address) {
        return tree.nodes[addr].left;
    }

    function getRight(Tree storage tree, address addr) internal view returns (address) {
        return tree.nodes[addr].right;
    }

    function getValue(Tree storage tree, address addr) internal view returns (uint256) {
        return tree.nodes[addr].value;
    }

    function getHash(Tree storage tree, address addr) internal view returns (bytes32) {
        return tree.nodes[addr].hashNode;
    }
}
