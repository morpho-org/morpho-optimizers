methods {
    initialized() returns bool envfree
    newAccount(address, address, uint256) envfree
    newNode(address, address, address, address) envfree
    setRoot(address, address) envfree

    getRoot(address) returns address envfree
    getCreated(address, address) returns bool envfree
    getLeft(address, address) returns address envfree
    getRight(address, address) returns address envfree
    getValue(address, address) returns uint256 envfree
    getHash(address, address) returns bytes32 envfree
    findAndClaimAt(address, address, address) envfree

    isWellFormed(address, address) returns bool envfree
}

definition isEmpty(address tree, address addr) returns bool =
    getLeft(tree, addr) == 0 &&
    getRight(tree, addr) == 0 &&
    getValue(tree, addr) == 0 &&
    getHash(tree, addr) == 0;

invariant notCreatedIsEmpty(address tree, address addr)
    ! getCreated(tree, addr) => isEmpty(tree, addr)

invariant zeroNotCreated(address tree, address addr)
    ! getCreated(tree, 0)

invariant rootZeroOrCreated(address tree)
    getRoot(tree) == 0 || getCreated(tree, getRoot(tree))

invariant wellFormed(address tree, address addr)
    isWellFormed(tree, addr)
    { preserved {
        require initialized();
        requireInvariant notCreatedIsEmpty(tree, addr);
      }
      preserved newNode(address _tree, address parent, address left, address right) {
        requireInvariant notCreatedIsEmpty(tree, parent);
        requireInvariant zeroNotCreated(tree, left);
        requireInvariant zeroNotCreated(tree, right);
      }
    }
