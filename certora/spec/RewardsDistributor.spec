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
}

definition isEmpty(address tree, address addr) returns bool =
    T.getLeft(tree, addr) == 0 &&
    T.getRight(tree, addr) == 0 &&
    T.getValue(tree, addr) == 0 &&
    T.getHash(tree, addr) == 0;

invariant notCreatedIsEmpty(address tree, address addr)
    ! T.getCreated(tree, addr) => T.isEmpty(tree, addr)
    filtered { f -> false }

invariant zeroNotCreated(address tree, address addr)
    ! T.getCreated(tree, 0)
    filtered { f -> false }

invariant rootZeroOrCreated(address tree)
    T.getRoot(tree) == 0 || T.getCreated(tree, T.getRoot(tree))
    filtered { f -> false }

invariant wellFormed(address tree, address addr)
    T.isWellFormed(tree, addr)
    filtered { f -> false }

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;  uint256 claimed;

    require (claimed <= _claimable);

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, claimed, _proof);

    assert lastReverted;
}

rule claimCorrectOne1(address tree, address _account, uint256 _claimable, bytes32 _proof) {
    env e;
    address root;
    address left;
    require root == T.getRoot(tree);
    require _account != 0;
    require T.getHash(tree, root) == currRoot();
    require T.getRight(tree, root) == _account;
    require T.getLeft(tree, root) == left;
    requireInvariant notCreatedIsEmpty(tree, root);
    requireInvariant wellFormed(tree, root);
    requireInvariant notCreatedIsEmpty(tree, _account);
    requireInvariant wellFormed(tree, _account);
    requireInvariant notCreatedIsEmpty(tree, left);
    requireInvariant wellFormed(tree, left);
    require T.getLeft(tree, _account) == 0;
    require T.getHash(tree, left) != T.getHash(tree, _account);

    bytes32 reconstructedLeaf;
    bytes32 reconstructedRoot;
    require reconstructedLeaf == _keccak(address_to_bytes32(_account), uint256_to_bytes32(_claimable));
    require reconstructedRoot == _keccak(_proof, reconstructedLeaf);

    claimOne(_account, _claimable, _proof);

    assert _proof == T.getHash(tree, left);
}

// rule claimCorrectOne2(address _account, uint256 _claimable, bytes32 _proof) {
//     env e;
//     address root;
//     address left;
//     require root == T.getRoot();
//     require _account != 0;
//     require T.getHash(root) == currRoot();
//     require T.getRight(root) == _account;
//     require T.getLeft(root) == left;
//     require T.isWellFormed(root);
//     require T.isWellFormed(_account);
//     require T.isWellFormed(left);
//     require T.getLeft(_account) == 0;

//     claimOne(_account, _claimable, _proof);

//     assert _claimable == T.getValue(_account);
// }

// rule claimCorrectOne3(address _account, uint256 _claimable, bytes32 _proof) {
//     env e;
//     address root;
//     address left;
//     require root == T.getRoot();
//     require _account != 0;
//     require T.getHash(root) == currRoot();
//     require T.getRight(root) == _account;
//     require T.getLeft(root) == left;
//     require T.isWellFormed(root);
//     require T.isWellFormed(_account);
//     require T.isWellFormed(left);
//     require T.getLeft(_account) == 0;

//     claimOne(_account, _claimable, _proof);

//     assert false;
// }

// rule embeddedHash(bytes32 claimable, bytes32 left, bytes32 left_alt, bytes32 right_hash, bytes32 currRoot) {
//     env e;
//     bytes32 left_hash; bytes32 left_alt_hash;
//     require left_hash == _keccak(left, claimable);
//     require left_alt_hash == _keccak(left_alt, claimable);
//     require _keccak(left_hash, right_hash) == currRoot;
//     require _keccak(left_alt_hash, right_hash) == currRoot;

//     assert left_alt == left;
// }

// rule claimOneAlt(address _account, uint256 _claimable, bytes32 _proof) {
//     env e;
//     address root;
//     require root == T.getRoot();
//     require T.getCreated(root);
//     require _account != 0;
//     require T.getHash(root) == currRoot();
//     require T.getRight(root) == _account;
//     requireInvariant wellFormed(root);

//     assert T.getLeft(root) != 0;
// }

// rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
//     env e;
//     require T.getHash(T.getRoot()) == currRoot();
//     require T.isWellFormed(_account); // can also assume that other accounts are well-formed

//     claim(_account, _claimable, _proof);

//     assert T.getCreated(T.getRoot());
//     assert T.getCreated(_account);
//     assert _claimable == T.getValue(_account);
// }

// // rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
// //     env e;
// //     require T.getHash(T.getRoot()) == currRoot();
// //     require T2.getHash(T2.getRoot()) == prevRoot();
// //     require T.isWellFormed(_account) && T2.isWellFormed(_account); // can also assume that other accounts are well-formed

// //     uint256 balanceBefore = MorphoToken.balanceOf(_account);
// //     uint256 claimedBefore = claimed(_account);

// //     claim(_account, _claimable, _proof);

// //     uint256 balanceAfter = MorphoToken.balanceOf(_account);

// //     assert balanceAfter - balanceBefore == _claimable - claimedBefore; 
// //     assert (T.getCreated(_account) && _claimable == T.getValue(_account)) || 
// //            (T2.getCreated(_account) && _claimable == T.getValue(_account));
// // }

// rule claimCompleteness(address _account) {
//     env e;
//     require T.getHash(T.getRoot()) == currRoot();
//     require T.getCreated(_account);
//     require T.isWellFormed(_account); // can also assume that other accounts are well-formed

//     T.findAndClaimAt@withrevert(currentContract, _account);

//     assert !lastReverted;
// }
