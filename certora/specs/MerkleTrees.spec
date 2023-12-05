methods {
    function newAccount(address, address, uint256) external envfree;
    function newNode(address, address, address, address) external envfree;
    function setRoot(address, address) external envfree;

    function getRoot(address) external returns address envfree;
    function getCreated(address, address) external returns bool envfree;
    function getLeft(address, address) external returns address envfree;
    function getRight(address, address) external returns address envfree;
    function getValue(address, address) external returns uint256 envfree;
    function getHash(address, address) external returns bytes32 envfree;
    function isWellFormed(address, address) external returns bool envfree;
}

definition isEmpty(address tree, address addr) returns bool =
    getLeft(tree, addr) == 0 &&
    getRight(tree, addr) == 0 &&
    getValue(tree, addr) == 0 &&
    getHash(tree, addr) == to_bytes32(0);

invariant zeroNotCreated(address tree)
    ! getCreated(tree, 0);

invariant rootZeroOrCreated(address tree)
    getRoot(tree) == 0 || getCreated(tree, getRoot(tree));

invariant notCreatedIsEmpty(address tree, address addr)
    ! getCreated(tree, addr) => isEmpty(tree, addr);

invariant wellFormed(address tree, address addr)
    isWellFormed(tree, addr)
    { preserved {
        requireInvariant notCreatedIsEmpty(tree, addr);
      }
      preserved newNode(address _, address parent, address left, address right) {
        requireInvariant notCreatedIsEmpty(tree, parent);
        requireInvariant zeroNotCreated(tree);
      }
    }
