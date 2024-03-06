// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./MerkleTreeLib.sol";

contract MerkleTrees {
    using MerkleTreeLib for MerkleTreeLib.Node;
    using MerkleTreeLib for MerkleTreeLib.Tree;

    mapping(address => MerkleTreeLib.Tree) trees;

    function newLeaf(
        address treeAddress,
        address addr,
        uint256 value
    ) public {
        trees[treeAddress].newLeaf(addr, value);
    }

    function newInternalNode(
        address treeAddress,
        address parent,
        address left,
        address right
    ) public {
        trees[treeAddress].newInternalNode(parent, left, right);
    }

    function setRoot(address treeAddress, address addr) public {
        trees[treeAddress].setRoot(addr);
    }

    function getRoot(address treeAddress) public view returns (address) {
        return trees[treeAddress].getRoot();
    }

    function getLeft(address treeAddress, address addr) public view returns (address) {
        return trees[treeAddress].getLeft(addr);
    }

    function getRight(address treeAddress, address addr) public view returns (address) {
        return trees[treeAddress].getRight(addr);
    }

    function getValue(address treeAddress, address addr) public view returns (uint256) {
        return trees[treeAddress].getValue(addr);
    }

    function getHash(address treeAddress, address addr) public view returns (bytes32) {
        return trees[treeAddress].getHash(addr);
    }

    function isEmpty(address treeAddress, address addr) public view returns (bool) {
        return trees[treeAddress].nodes[addr].isEmpty();
    }

    function isWellFormed(address treeAddress, address addr) public view returns (bool) {
        return trees[treeAddress].isWellFormed(addr);
    }

    // Check that the nodes are well formed on the path from the root.
    // Stops early if the proof is incorrect.
    function wellFormedPath(
        address treeAddress,
        address addr,
        bytes32[] memory proof
    ) public view {
        MerkleTreeLib.Tree storage tree = trees[treeAddress];

        require(tree.isWellFormed(addr));

        for (uint256 i = proof.length; i > 0; i--) {
            bytes32 otherHash = proof[i - 1];

            address left = tree.getLeft(addr);
            address right = tree.getRight(addr);
            if (tree.getHash(left) == otherHash) {
                addr = right;
            } else if (tree.getHash(right) == otherHash) {
                addr = left;
            } else {
                return;
            }

            require(tree.isWellFormed(addr));
        }
    }
}
