// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
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
        address addr;
        address left;
        address right;
    }

    function testVerifyCertificate() public {
        string memory projectRoot = vm.projectRoot();
        string memory path = string.concat(projectRoot, "/certora/checker/certificate.json");
        string memory json = vm.readFile(path);

        uint256 leafLength = abi.decode(json.parseRaw(".leafLength"), (uint256));
        Leaf memory leaf;
        for (uint256 i; i < leafLength; i++) {
            leaf = abi.decode(
                json.parseRaw(string.concat(".leaf[", Strings.toString(i), "]")),
                (Leaf)
            );
            tree.newAccount(leaf.addr, leaf.value);
        }

        uint256 nodeLength = abi.decode(json.parseRaw(".nodeLength"), (uint256));
        InternalNode memory node;
        for (uint256 i; i < nodeLength; i++) {
            node = abi.decode(
                json.parseRaw(string.concat(".node[", Strings.toString(i), "]")),
                (InternalNode)
            );
            tree.newNode(node.addr, node.left, node.right);
        }

        bytes32 root = abi.decode(json.parseRaw(".root"), (bytes32));

        assertTrue(tree.getCreated(node.addr), "unrecognized node");
        assertEq(tree.getHash(node.addr), root, "mismatched roots");
    }
}
