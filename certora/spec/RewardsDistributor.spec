using MerkleTreeMock as T
using MorphoToken as MorphoToken

methods {
    MORPHO() returns address envfree
    currRoot() returns bytes32 envfree
    claimed(address) returns uint256 envfree
    claim(address, uint256, bytes32[]) envfree => DISPATCHER(true)
    claimOne(address, uint256, bytes32) envfree
    transfer(address, uint256) => DISPATCHER(true)
    address_to_bytes32(address) returns bytes32 envfree
    uint256_to_bytes32(uint256) returns bytes32 envfree

    T.initialized(address) returns bool envfree
    T.newAccount(address, address, uint256) envfree
    T.newNode(address, address, address, address) envfree
    T.setRoot(address, address) envfree
    T.isWellFormed(address, address) returns bool envfree
    T.findProof(address, address) returns bytes32[] envfree
    T.getRoot(address) returns address envfree
    T.getCreated(address, address) returns bool envfree
    T.getLeft(address, address) returns address envfree
    T.getRight(address, address) returns address envfree
    T.getValue(address, address) returns uint256 envfree
    T.getHash(address, address) returns bytes32 envfree
    T.findAndClaimAt(address, address, address) envfree

    MorphoToken.balanceOf(address) returns uint256 envfree

    keccak(bytes32 a, bytes32 b) returns bytes32 envfree => _keccak(a, b)
}

ghost _keccak(bytes32, bytes32) returns bytes32 {
    axiom forall bytes32 a1. forall bytes32 b1. forall bytes32 a2. forall bytes32 b2.
        _keccak(a1, b1) == _keccak(a2, b2) => a1 == a2 && b1 == b2;
    axiom forall bytes32 a. forall bytes32 b. _keccak(a, b) != 0;
    axiom forall address tree. forall address addr. isCreatedWellFormed(tree, addr);
}

definition isEmpty(address tree, address addr) returns bool =
    T.getLeft(tree, addr) == 0 &&
    T.getRight(tree, addr) == 0 &&
    T.getValue(tree, addr) == 0 &&
    T.getHash(tree, addr) == 0;

definition isCreatedWellFormed(address tree, address addr) returns bool =
    T.isWellFormed(tree, addr) &&
    (! T.getCreated(tree, addr) => T.isEmpty(tree, addr));

invariant zeroNotCreated(address tree)
    ! T.getCreated(tree, 0)
    filtered { f -> false }

invariant rootZeroOrCreated(address tree)
    T.getRoot(tree) == 0 || T.getCreated(tree, T.getRoot(tree))
    filtered { f -> false }

function safeAssumptions(address tree) {
    requireInvariant zeroNotCreated(tree);
    requireInvariant rootZeroOrCreated(tree);
}

invariant createdWellFormed(address tree, address addr)
    isCreatedWellFormed(tree, addr)
    filtered { f -> false }

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;  uint256 claimed;

    require (claimed <= _claimable);

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, claimed, _proof);

    assert lastReverted;
}

rule claimCorrectOne(address _account, uint256 _claimable, bytes32 _proof) {
    env e; address tree; address root; address left;
    require root == T.getRoot(tree);

    require T.getHash(tree, root) == currRoot();
    require T.getRight(tree, root) == _account;
    require T.getLeft(tree, root) == left;
    require _account != 0;

    address leftLeft; address rightLeft; address leftAccount; address rightAccount;
    require leftLeft == T.getLeft(tree, left);
    require rightLeft == T.getRight(tree, left);
    require leftAccount == T.getLeft(tree, _account);
    require rightAccount == T.getRight(tree, _account);

    uint256 leftValue; uint256 accountValue;
    require leftValue == T.getValue(tree, left);
    require accountValue == T.getValue(tree, _account);

    bytes32 leftHash; bytes32 accountHash;
    require leftHash == T.getHash(tree, left);
    require accountHash == T.getHash(tree, _account);

    bytes32 leftLeftHash; bytes32 rightLeftHash; bytes32 leftAccountHash; bytes32 rightAccountHash;
    require leftLeftHash == T.getHash(tree, leftLeft);
    require rightLeftHash == T.getHash(tree, rightLeft);
    require leftAccountHash == T.getHash(tree, leftAccount);
    require rightAccountHash == T.getHash(tree, rightAccount);

    safeAssumptions(tree);
    requireInvariant createdWellFormed(tree, root);
    requireInvariant createdWellFormed(tree, _account);
    requireInvariant createdWellFormed(tree, left);
    requireInvariant createdWellFormed(tree, leftLeft);
    requireInvariant createdWellFormed(tree, rightLeft);
    requireInvariant createdWellFormed(tree, leftAccount);
    requireInvariant createdWellFormed(tree, rightAccount);

    claimOne(_account, _claimable, _proof);

    assert _claimable == T.getValue(tree, _account);
}

rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
    env e; address tree; address root;
    require root == T.getRoot(tree);

    require T.getHash(tree, root) == currRoot();

    requireInvariant createdWellFormed(tree, _account);

    claim(_account, _claimable, _proof);

    assert _claimable == T.getValue(tree, _account);
}

// rule claimCorrectnessStrong(address _account, uint256 _claimable, bytes32[] _proof) {
//     env e; address tree1; address root1; address tree2; address root2;
//     require root1 == T.getRoot(tree1);
//     require root2 == T.getRoot(tree2);

//     require T.getHash(tree1, root1) == currRoot();
//     require T.getHash(tree2, root2) == prevRoot();
//     require T.isWellFormed(tree1, _account);
//     require T.isWellFormed(tree2, _account);

//     uint256 balanceBefore = MorphoToken.balanceOf(_account);
//     uint256 claimedBefore = claimed(_account);

//     claim(_account, _claimable, _proof);

//     uint256 balanceAfter = MorphoToken.balanceOf(_account);

//     assert balanceAfter - balanceBefore == _claimable - claimedBefore;
//     assert (T.getCreated(tree1, _account) && _claimable == T.getValue(tree1, _account)) ||
//            (T.getCreated(tree2, _account) && _claimable == T.getValue(tree2, _account));
// }

rule claimCompleteness(address _account) {
    env e; address tree; address root;
    require root == T.getRoot(tree);

    require T.getHash(tree, root) == currRoot();
    require T.getCreated(tree, _account);
    requireInvariant createdWellFormed(tree, _account);

    T.findAndClaimAt@withrevert(tree, currentContract, _account);

    assert !lastReverted;
}
