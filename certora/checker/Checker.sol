// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../lib/morpho-utils/lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import "../helpers/MerkleTreeLib.sol";
import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/StdJson.sol";

contract Checker is Test {
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using stdJson for string;

    MerkleTreeLib.Tree internal tree;

    function testVerifyCertificate() public {
        string memory projectRoot = vm.projectRoot();
        string memory path = string.concat(projectRoot, "/certificate.json");
        string memory json = vm.readFile(path);

        uint256 leafLength = abi.decode(json.parseRaw(".leafLength"), (uint256));
        MerkleTreeLib.Leaf memory leaf;
        for (uint256 i; i < leafLength; i++) {
            leaf = abi.decode(
                json.parseRaw(string.concat(".leaf[", Strings.toString(i), "]")),
                (MerkleTreeLib.Leaf)
            );
            tree.newLeaf(leaf);
        }

        uint256 nodeLength = abi.decode(json.parseRaw(".nodeLength"), (uint256));
        MerkleTreeLib.InternalNode memory node;
        for (uint256 i; i < nodeLength; i++) {
            node = abi.decode(
                json.parseRaw(string.concat(".node[", Strings.toString(i), "]")),
                (MerkleTreeLib.InternalNode)
            );
            tree.newInternalNode(node);
        }

        assertTrue(!tree.isEmpty(node.addr), "empty root");

        uint256 total = abi.decode(json.parseRaw(".total"), (uint256));
        assertEq(tree.getValue(node.addr), total, "incorrect total rewards");

        bytes32 root = abi.decode(json.parseRaw(".root"), (bytes32));
        assertEq(tree.getHash(node.addr), root, "mismatched roots");
    }
}
