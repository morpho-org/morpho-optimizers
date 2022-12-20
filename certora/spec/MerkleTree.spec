methods {
    root() returns address envfree
    initialized() returns bool envfree
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

invariant notCreated(address addr)
    ! getCreated(addr) => isEmpty(addr)

invariant wellFormed(address addr)
    isWellFormed(addr)
    { preserved {
        require initialized();
        requireInvariant notCreated(addr);
      }
    }
