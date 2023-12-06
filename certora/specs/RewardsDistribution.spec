using MerkleTrees as MerkleTrees;
using MorphoToken as MorphoToken;

methods {
    function currRoot() external returns bytes32 envfree;
    function claim(address, uint256, bytes32[]) external envfree;

    function MerkleTrees.getValue(address, address) external returns uint256 envfree;
    function MerkleTrees.getHash(address, address) external returns bytes32 envfree;
    function MerkleTrees.wellFormedUpTo(address, address, uint256) external envfree;

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

    require MerkleTrees.getHash(tree, root) == currRoot();

    MerkleTrees.wellFormedUpTo(tree, root, 3);

    claim(_account, _claimable, _proof);

    assert _claimable == MerkleTrees.getValue(tree, _account);
}
