using MerkleTreeMock as T;
using MorphoToken as MorphoToken;

methods {
    function MORPHO() external returns address envfree;
    function currRoot() external returns bytes32 envfree;
    function claimed(address) external returns uint256 envfree;
    function claim(address, uint256, bytes32[]) external envfree;
    function claimOne(address, uint256, bytes32) external envfree;
    function address_to_bytes32(address) external returns bytes32 envfree;
    function uint256_to_bytes32(uint256) external returns bytes32 envfree;

    function T.initialized() external returns bool envfree;
    function T.newAccount(address, address, uint256) external envfree;
    function T.newNode(address, address, address, address) external envfree;
    function T.setRoot(address, address) external envfree;
    function T.isWellFormed(address, address) external returns bool envfree;
    function T.getRoot(address) external returns address envfree;
    function T.getCreated(address, address) external returns bool envfree;
    function T.getLeft(address, address) external returns address envfree;
    function T.getRight(address, address) external returns address envfree;
    function T.getValue(address, address) external returns uint256 envfree;
    function T.getHash(address, address) external returns bytes32 envfree;
    function T.findAndClaimAt(address, address, address) external envfree;

    function MorphoToken.transfer(address, uint256) external;
    function MorphoToken.balanceOf(address) external returns uint256 envfree;

    function _.keccak(bytes32 a, bytes32 b) internal => _keccak(a, b) expect bytes32 ALL;
}

ghost _keccak(bytes32, bytes32) returns bytes32 {
    axiom forall bytes32 a1. forall bytes32 b1. forall bytes32 a2. forall bytes32 b2.
        _keccak(a1, b1) == _keccak(a2, b2) => a1 == a2 && b1 == b2;
    axiom forall bytes32 a. forall bytes32 b. _keccak(a, b) != to_bytes32(0);
    axiom forall address tree. forall address addr. isCreatedWellFormed(tree, addr);
}

definition isEmpty(address tree, address addr) returns bool =
    T.getLeft(tree, addr) == 0 &&
    T.getRight(tree, addr) == 0 &&
    T.getValue(tree, addr) == 0 &&
    T.getHash(tree, addr) == to_bytes32(0);

definition isCreatedWellFormed(address tree, address addr) returns bool =
    T.isWellFormed(tree, addr) &&
    (! T.getCreated(tree, addr) => isEmpty(tree, addr));

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
