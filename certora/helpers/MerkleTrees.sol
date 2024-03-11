// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./MerkleTreeLib.sol";

contract MerkleTrees {
    using MerkleTreeLib for MerkleTreeLib.Node;
    using MerkleTreeLib for MerkleTreeLib.Tree;

    mapping(address => MerkleTreeLib.Tree) trees;

    function newLeaf(address treeAddress, MerkleTreeLib.Leaf memory leaf) public {
        trees[treeAddress].newLeaf(leaf);
    }

    function newInternalNode(address treeAddress, MerkleTreeLib.InternalNode memory internalNode)
        public
    {
        trees[treeAddress].newInternalNode(internalNode);
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
    function wellFormedPath(
        address treeAddress,
        address addr,
        bytes32[] memory proof
    ) public view {
        MerkleTreeLib.Tree storage tree = trees[treeAddress];

        for (uint256 i = proof.length; ; ) {
            require(tree.isWellFormed(addr));

            if (i == 0) break;

            bytes32 otherHash = proof[--i];

            address left = tree.getLeft(addr);
            address right = tree.getRight(addr);

            addr = tree.getHash(left) == otherHash ? right : left;
        }
    }
}
