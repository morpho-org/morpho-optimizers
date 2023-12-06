using MerkleTrees as T;
using ERC20 as MorphoToken;

methods {
    function currRoot() external returns bytes32 envfree;
    function claim(address, uint256, bytes32[]) external envfree;

    function T.getValue(address, address) external returns uint256 envfree;
    function T.getHash(address, address) external returns bytes32 envfree;
    function T.fullyCreatedWellFormed(address, address, uint256) external envfree;

    function MorphoToken.balanceOf(address) external returns uint256 envfree;
}

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;  uint256 claimed;

    require (claimed <= _claimable);

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, claimed, _proof);

    assert lastReverted;
}

rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
    address tree; address root;

    // No need to make sure that currRoot is the root of the tree: one can pass an internal node instead.

    require T.getHash(tree, root) == currRoot();

    T.fullyCreatedWellFormed(tree, root, 3);

    claim(_account, _claimable, _proof);

    assert _claimable == T.getValue(tree, _account);
}
