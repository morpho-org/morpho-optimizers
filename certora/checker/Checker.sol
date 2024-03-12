// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../lib/morpho-utils/lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import "../helpers/MerkleTrees.sol";
import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/StdJson.sol";

contract Checker is Test {
    using stdJson for string;

    MerkleTrees trees = new MerkleTrees();
    address constant tree = address(0);

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
            trees.newLeaf(tree, leaf);
        }

        uint256 nodeLength = abi.decode(json.parseRaw(".nodeLength"), (uint256));
        MerkleTreeLib.InternalNode memory node;
        for (uint256 i; i < nodeLength; i++) {
            node = abi.decode(
                json.parseRaw(string.concat(".node[", Strings.toString(i), "]")),
                (MerkleTreeLib.InternalNode)
            );
            trees.newInternalNode(tree, node);
        }

        // At this point `node` is the candidate for the root.

        assertTrue(!trees.isEmpty(tree, node.addr), "empty root");

        uint256 total = abi.decode(json.parseRaw(".total"), (uint256));
        assertEq(trees.getValue(tree, node.addr), total, "incorrect total rewards");

        bytes32 root = abi.decode(json.parseRaw(".root"), (bytes32));
        assertEq(trees.getHash(tree, node.addr), root, "mismatched roots");
    }
}
