methods {
    initialized() returns bool envfree
    newAccount(address, uint256) envfree
    newNode(address, address, address) envfree
    setRoot(address) envfree

    getRoot() returns address envfree
    getCreated(address) returns bool envfree
    getLeft(address) returns address envfree
    getRight(address) returns address envfree
    getValue(address) returns uint256 envfree
    getHash(address) returns bytes32 envfree
    findAndClaimAt(address, address) envfree

    isWellFormed(address) returns bool envfree

    claim(address, uint256, bytes32[]) envfree => DISPATCHER(true)
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

invariant rootZeroOrCreated()
    getRoot() == 0 || getCreated(getRoot())

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
