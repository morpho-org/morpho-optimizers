methods {
    function newInternalNode(address, address, address, address) external envfree;

    function getRoot(address) external returns address envfree;
    function getCreated(address, address) external returns bool envfree;
    function isWellFormed(address, address) external returns bool envfree;
}

invariant zeroNotCreated(address tree)
    ! getCreated(tree, 0);

invariant rootZeroOrCreated(address tree)
    getRoot(tree) == 0 || getCreated(tree, getRoot(tree));

invariant wellFormed(address tree, address addr)
    isWellFormed(tree, addr)
    { preserved {
        requireInvariant zeroNotCreated(tree);
        requireInvariant wellFormed(tree, addr);
      }
    }
