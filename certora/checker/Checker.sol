// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../helpers/MerkleTreeLib.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

contract Checker is Test {
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using stdJson for string;

    MerkleTreeLib.Tree public tree;

    struct Leaf {
        address addr;
        uint256 value;
    }

    struct InternalNode {
        address left;
        address right;
    }

    function testZeroDepthTree() public {
        string memory projectRoot = vm.projectRoot();
        string memory path = string.concat(projectRoot, "/certora/checker/simple_proofs.json");
        string memory json = vm.readFile(path);

        Leaf memory leaf1 = abi.decode(json.parseRaw(".leaf1"), (Leaf));
        tree.newAccount(leaf1.addr, leaf1.value);

        Leaf memory leaf2 = abi.decode(json.parseRaw(".leaf2"), (Leaf));
        tree.newAccount(leaf2.addr, leaf2.value);

        InternalNode memory node1 = abi.decode(json.parseRaw(".node1"), (InternalNode));
        tree.newNode(address(1), node1.right, node1.left);

        console.logBytes32(tree.getHash(address(1)));
    }
}
