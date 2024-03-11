// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./MerkleTreeLib.sol";

contract MerkleTrees {
    using MerkleTreeLib for MerkleTreeLib.Node;
    using MerkleTreeLib for MerkleTreeLib.Tree;

    mapping(address => MerkleTreeLib.Tree) internal trees;

    function newLeaf(address tree, MerkleTreeLib.Leaf memory leaf) public {
        trees[tree].newLeaf(leaf);
    }

    function newInternalNode(address tree, MerkleTreeLib.InternalNode memory internalNode) public {
        trees[tree].newInternalNode(internalNode);
    }

    function getLeft(address tree, address node) public view returns (address) {
        return trees[tree].nodes[node].left;
    }

    function getRight(address tree, address node) public view returns (address) {
        return trees[tree].nodes[node].right;
    }

    function getValue(address tree, address node) public view returns (uint256) {
        return trees[tree].nodes[node].value;
    }

    function getHash(address tree, address node) public view returns (bytes32) {
        return trees[tree].nodes[node].hashNode;
    }

    function isEmpty(address tree, address node) public view returns (bool) {
        return trees[tree].nodes[node].isEmpty();
    }

    function isWellFormed(address tree, address node) public view returns (bool) {
        return trees[tree].isWellFormed(node);
    }

    // Check that the nodes are well formed on the path from the root.
    function wellFormedPath(
        address tree,
        address node,
        bytes32[] memory proof
    ) public view {
        for (uint256 i = proof.length; ; ) {
            require(isWellFormed(tree, node));

            if (i == 0) break;

            bytes32 otherHash = proof[--i];

            address left = getLeft(tree, node);
            address right = getRight(tree, node);

            node = getHash(tree, left) == otherHash ? right : left;
        }
    }
}
