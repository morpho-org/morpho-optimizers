// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

library MerkleTreeLib {
    struct Node {
        bool created;
        address left;
        address right;
        uint256 value;
        bytes32 hashNode;
    }

    struct Tree {
        mapping(address => Node) nodes;
        address root;
    }

    function newAccount(
        Tree storage tree,
        address addr,
        uint256 value
    ) public {
        Node storage node = tree.nodes[addr];
        require(addr != address(0));
        require(!node.created);
        require(value != 0);

        node.created = true;
        node.value = value;
        node.hashNode = keccak256(abi.encodePacked(addr, value));
        require(node.hashNode << 160 != 0);
    }

    function newNode(
        Tree storage tree,
        address parent,
        address left,
        address right
    ) public {
        Node storage parentNode = tree.nodes[parent];
        Node storage leftNode = tree.nodes[left];
        Node storage rightNode = tree.nodes[right];
        require(parent != address(0));
        require(!parentNode.created);
        require(leftNode.created && rightNode.created);
        require(leftNode.hashNode <= rightNode.hashNode);

        parentNode.created = true;
        parentNode.left = left;
        parentNode.right = right;
        parentNode.hashNode = keccak256(abi.encode(leftNode.hashNode, rightNode.hashNode));
        require(parentNode.hashNode << 160 != 0);
    }

    function setRoot(Tree storage tree, address addr) public {
        require(tree.nodes[addr].created);
        tree.root = addr;
    }

    function isWellFormed(Tree storage tree, address addr) public view returns (bool) {
        Node storage node = tree.nodes[addr];

        if (!node.created) return true;

        if (node.hashNode << 160 == 0) return false;

        if (node.left == address(0) && node.right == address(0)) {
            return
                node.value != 0 && node.hashNode == keccak256(abi.encodePacked(addr, node.value));
        } else {
            // Well-formed nodes have exactly 0 or 2 children.
            if (node.left == address(0) || node.right == address(0)) return false;
            Node storage left = tree.nodes[node.left];
            Node storage right = tree.nodes[node.right];
            bool sorted = left.hashNode <= right.hashNode; // Well-formed tree.nodes should be pair sorted.
            return
                left.created &&
                right.created &&
                node.value == 0 &&
                sorted &&
                node.hashNode == keccak256(abi.encode(left.hashNode, right.hashNode));
        }
    }

    function findProof(Tree storage, address) public pure returns (bytes32[] memory) {
        return new bytes32[](0); // TODO
    }

    function getRoot(Tree storage tree) public view returns (address) {
        return tree.root;
    }

    function getCreated(Tree storage tree, address addr) public view returns (bool) {
        return tree.nodes[addr].created;
    }

    function getLeft(Tree storage tree, address addr) public view returns (address) {
        return tree.nodes[addr].left;
    }

    function getRight(Tree storage tree, address addr) public view returns (address) {
        return tree.nodes[addr].right;
    }

    function getValue(Tree storage tree, address addr) public view returns (uint256) {
        return tree.nodes[addr].value;
    }

    function getHash(Tree storage tree, address addr) public view returns (bytes32) {
        return tree.nodes[addr].hashNode;
    }
}
