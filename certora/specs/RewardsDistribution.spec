using MerkleTrees as T;
using ERC20 as MorphoToken;

methods {
    function MORPHO() external returns address envfree;
    function currRoot() external returns bytes32 envfree;
    function claimed(address) external returns uint256 envfree;
    function claim(address, uint256, bytes32[]) external envfree;

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

rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
    env e; address tree; address root;
    require root == T.getRoot(tree);

    require T.getHash(tree, root) == currRoot();

    requireInvariant createdWellFormed(tree, _account);

    claim(_account, _claimable, _proof);

    assert _claimable == T.getValue(tree, _account);
}

rule claimCorrectnessZero(address _account, uint256 _claimable, bytes32[] _proof) {
    env e; address tree; address root;
    require root == T.getRoot(tree);

    require T.getHash(tree, root) == currRoot();

    requireInvariant createdWellFormed(tree, _account);
    requireInvariant createdWellFormed(tree, root);

    require _proof.length == 0;

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
