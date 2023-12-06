using MerkleTrees as MerkleTrees;
using MorphoToken as MorphoToken;

methods {
    function prevRoot() external returns bytes32 envfree;
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
    address prevTree; address prevNode;
    address currTree; address currNode;

    // No need to make sure that currNode (resp prevNode) is equal to currRoot (resp prevRoot): one can pass an internal node instead.

    require MerkleTrees.getHash(prevTree, prevNode) == prevRoot();
    MerkleTrees.wellFormedUpTo(prevTree, prevNode, 3);

    require MerkleTrees.getHash(currTree, currNode) == currRoot();
    MerkleTrees.wellFormedUpTo(currTree, currNode, 3);

    claim(_account, _claimable, _proof);

    assert _claimable == MerkleTrees.getValue(currTree, _account) ||
           _claimable == MerkleTrees.getValue(prevTree, _account);
}
