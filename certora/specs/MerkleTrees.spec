methods {
    function newInternalNode(address, address, address, address) external envfree;

    function getRoot(address) external returns address envfree;
    function getValue(address, address) external returns uint256 envfree;
    function isEmpty(address, address) external returns bool envfree;
    function isWellFormed(address, address) external returns bool envfree;
}

invariant zeroIsEmpty(address tree)
    isEmpty(tree, 0);

invariant nonEmptyHasValue(address tree, address addr)
    ! isEmpty(tree, addr) => getValue(tree, addr) != 0
{ preserved newInternalNode(address _, address parent, address left, address right) {
    requireInvariant nonEmptyHasValue(tree, left);
    requireInvariant nonEmptyHasValue(tree, right);
  }
}

invariant rootIsZeroOrNotEmpty(address tree)
    getRoot(tree) == 0 || !isEmpty(tree, getRoot(tree));

invariant wellFormed(address tree, address addr)
    isWellFormed(tree, addr)
{ preserved {
    requireInvariant zeroIsEmpty(tree);
  }
  preserved newInternalNode(address _, address parent, address left, address right) {
    requireInvariant zeroIsEmpty(tree);
    requireInvariant nonEmptyHasValue(tree, left);
    requireInvariant nonEmptyHasValue(tree, right);
  }
}
