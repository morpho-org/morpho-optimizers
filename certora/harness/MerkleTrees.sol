// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./MerkleTreeLib.sol";
import "src/common/rewards-distribution/RewardsDistributor.sol";

contract MerkleTrees {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    mapping(address => MerkleTreeLib.Tree) trees;

    function newAccount(
        address treeAddress,
        address addr,
        uint256 value
    ) public {
        trees[treeAddress].newAccount(addr, value);
    }

    function newNode(
        address treeAddress,
        address parent,
        address left,
        address right
    ) public {
        trees[treeAddress].newNode(parent, left, right);
    }

    function setRoot(address treeAddress, address addr) public {
        trees[treeAddress].setRoot(addr);
    }

    function isWellFormed(address treeAddress, address addr) public view returns (bool) {
        return trees[treeAddress].isWellFormed(addr);
    }

    function getRoot(address treeAddress) public view returns (address) {
        return trees[treeAddress].getRoot();
    }

    function getCreated(address treeAddress, address addr) public view returns (bool) {
        return trees[treeAddress].getCreated(addr);
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

    function fullyCreatedWellFormed(address treeAddress, address addr) public view {
        require(trees[treeAddress].isWellFormed(addr));
        require(
            trees[treeAddress].getCreated(addr) ||
                (trees[treeAddress].getLeft(addr) == address(0) &&
                    trees[treeAddress].getRight(addr) == address(0) &&
                    trees[treeAddress].getValue(addr) &&
                    trees[treeAddress].getHash(addr) == bytes(0))
        );

        address left = trees[treeAddress].getLeft(addr);
        address right = trees[treeAddress].getRight(addr);
        if (left != address(0)) {
            fullyCreatedWellFormed(treeAddress, left);
            fullyCreatedWellFormed(treeAddress, right);
        }
    }
}
