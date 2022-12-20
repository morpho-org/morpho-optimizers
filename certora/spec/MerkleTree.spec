methods {
    root() returns address envfree
    initialized() returns bool envfree
    newAccount(address, uint256) envfree
    newNode(address, address, address) envfree
    setRoot(address) envfree

    getCreated(address) returns bool envfree
    getLeft(address) returns address envfree
    getRight(address) returns address envfree
    getValue(address) returns uint256 envfree
    getHash(address) returns bytes32 envfree

    isWellFormed(address) returns bool envfree
}

definition isEmpty(address addr) returns bool =
    getLeft(addr) == 0 &&
    getRight(addr) == 0 &&
    getValue(addr) == 0 &&
    getHash(addr) == 0;

invariant notCreatedIsEmpty(address addr)
    ! getCreated(addr) => isEmpty(addr)

invariant zeroNotCreated(address addr)
    ! getCreated(0)

invariant wellFormed(address addr)
    isWellFormed(addr)
    { preserved {
        require initialized();
        requireInvariant notCreatedIsEmpty(addr);
      }
      preserved newNode(address parent, address left, address right) {
        requireInvariant notCreatedIsEmpty(parent);
        requireInvariant zeroNotCreated(left);
        requireInvariant zeroNotCreated(right);
      }
    }
