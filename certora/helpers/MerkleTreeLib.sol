// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

library MerkleTreeLib {
    using MerkleTreeLib for Node;

    struct Leaf {
        address addr;
        uint256 value;
    }

    struct InternalNode {
        address addr;
        address left;
        address right;
    }

    struct Node {
        address left;
        address right;
        uint256 value;
        // hash of [addr, value] for leaves, and [left.hash, right.hash] for internal nodes.
        bytes32 hashNode;
    }

    function isEmpty(Node memory node) internal pure returns (bool) {
        return
            node.left == address(0) &&
            node.right == address(0) &&
            node.value == 0 &&
            node.hashNode == bytes32(0);
    }

    // The tree has no root because every node (and the nodes underneath) form a Merkle tree.
    struct Tree {
        mapping(address => Node) nodes;
    }

    function newLeaf(Tree storage tree, Leaf memory leaf) internal {
        // The address of the receiving account is used as the key to create a new leaf.
        // This ensures that a single account cannot appear twice in the tree.
        Node storage node = tree.nodes[leaf.addr];
        require(leaf.addr != address(0), "addr is zero address");
        require(node.isEmpty(), "leaf is not empty");
        require(leaf.value != 0, "value is zero");

        node.value = leaf.value;
        node.hashNode = keccak256(abi.encodePacked(leaf.addr, leaf.value));
    }

    function newInternalNode(Tree storage tree, InternalNode memory internalNode) internal {
        // The key of the new internal node is left arbitrary.
        Node storage node = tree.nodes[internalNode.addr];
        Node storage leftNode = tree.nodes[internalNode.left];
        Node storage rightNode = tree.nodes[internalNode.right];
        require(internalNode.addr != address(0), "node is zero address");
        require(node.isEmpty(), "node is not empty");
        require(!leftNode.isEmpty(), "left is empty");
        require(!rightNode.isEmpty(), "right is empty");
        require(leftNode.hashNode <= rightNode.hashNode, "children are not pair sorted");

        node.left = internalNode.left;
        node.right = internalNode.right;
        // The value of an internal node represents the sum of the values of the leaves underneath.
        node.value = leftNode.value + rightNode.value;
        node.hashNode = keccak256(abi.encode(leftNode.hashNode, rightNode.hashNode));
    }

    // The specification of a well-formed tree is the following:
    //   - empty nodes are well-formed
    //   - other nodes should have non-zero value, where the leaf node contains the value of the account and internal nodes contain the sum of the values of its leaf children.
    //   - correct hashing of leaves and of internal nodes
    //   - internal nodes have their children pair sorted and not empty
    function isWellFormed(Tree storage tree, address addr) internal view returns (bool) {
        Node storage node = tree.nodes[addr];

        if (node.isEmpty()) return true;

        if (node.value == 0) return false;

        if (node.left == address(0) && node.right == address(0)) {
            return node.hashNode == keccak256(abi.encodePacked(addr, node.value));
        } else {
            // Well-formed nodes have exactly 0 or 2 children.
            if (node.left == address(0) || node.right == address(0)) return false;
            Node storage left = tree.nodes[node.left];
            Node storage right = tree.nodes[node.right];
            return
                !left.isEmpty() &&
                !right.isEmpty() &&
                node.value == left.value + right.value &&
                left.hashNode <= right.hashNode &&
                node.hashNode == keccak256(abi.encode(left.hashNode, right.hashNode));
        }
    }

    function isEmpty(Tree storage tree, address addr) internal view returns (bool) {
        return tree.nodes[addr].isEmpty();
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
