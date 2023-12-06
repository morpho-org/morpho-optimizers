using MerkleTrees as MerkleTrees;
using MorphoToken as MorphoToken;

methods {
    function prevRoot() external returns bytes32 envfree;
    function currRoot() external returns bytes32 envfree;
    function claimed(address) external returns uint256 envfree;
    function claim(address, uint256, bytes32[]) external envfree;

    function MerkleTrees.getValue(address, address) external returns uint256 envfree;
    function MerkleTrees.getHash(address, address) external returns bytes32 envfree;
    function MerkleTrees.wellFormedUpTo(address, address, uint256) external envfree;

    function MorphoToken.balanceOf(address) external returns uint256 envfree;
}

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    claim(_account, _claimable, _proof);

    uint256 _claimable2;
    require (_claimable2 <= _claimable);
    claim@withrevert(_account, _claimable2, _proof);

    assert lastReverted;
}

rule transferredTokens(address _account, uint256 _claimable, bytes32[] _proof) {
    require _account != currentContract;

    uint256 balanceBefore = MorphoToken.balanceOf(_account);
    uint256 claimedBefore = claimed(_account);

    claim(_account, _claimable, _proof);

    uint256 balanceAfter = MorphoToken.balanceOf(_account);

    assert balanceAfter - balanceBefore == _claimable - claimedBefore;
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
