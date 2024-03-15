// SPDX-License-Identifier: AGPL-3.0-only

methods {
    function newInternalNode(address, MerkleTreeLib.InternalNode) external envfree;

    function getValue(address, address) external returns(uint256) envfree;
    function isEmpty(address, address) external returns(bool) envfree;
    function isWellFormed(address, address) external returns(bool) envfree;
}

invariant zeroIsEmpty(address tree)
    isEmpty(tree, 0);

invariant nonEmptyHasValue(address tree, address addr)
    ! isEmpty(tree, addr) => getValue(tree, addr) != 0
{ preserved newInternalNode(address _, MerkleTreeLib.InternalNode internalNode) {
    requireInvariant nonEmptyHasValue(tree, internalNode.left);
    requireInvariant nonEmptyHasValue(tree, internalNode.right);
  }
}

invariant wellFormed(address tree, address addr)
    isWellFormed(tree, addr)
{ preserved {
    requireInvariant zeroIsEmpty(tree);
  }
  preserved newInternalNode(address _, MerkleTreeLib.InternalNode internalNode) {
    requireInvariant zeroIsEmpty(tree);
    requireInvariant nonEmptyHasValue(tree, internalNode.left);
    requireInvariant nonEmptyHasValue(tree, internalNode.right);
  }
}
