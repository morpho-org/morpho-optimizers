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

// Check an account can only claim greater rewards each time.
rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    claim(_account, _claimable, _proof);

    assert _claimable == claimed(_account);

    uint256 _claimable2;
    // Assume that the second claim is smaller or equal to the previous claimed amount.
    require (_claimable2 <= _claimable);
    claim@withrevert(_account, _claimable2, _proof);

    assert lastReverted;
}

// Check that the transferred amount is equal to the claimed amount minus the previous claimed amount.
rule transferredTokens(address _account, uint256 _claimable, bytes32[] _proof) {
    // Assume that the rewards distributor itself is not receiving the tokens, to simplify this rule.
    require _account != currentContract;

    uint256 balanceBefore = MorphoToken.balanceOf(_account);
    uint256 claimedBefore = claimed(_account);

    // Safe require because the sum is capped by the total supply.
    require balanceBefore + MorphoToken.balanceOf(currentContract) < 2^256;

    claim(_account, _claimable, _proof);

    uint256 balanceAfter = MorphoToken.balanceOf(_account);

    assert balanceAfter - balanceBefore == _claimable - claimedBefore;
}

rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
    address prevTree; address prevNode;
    address currTree; address currNode;

    // Assume that prevRoot and currRoot correspond to prevTree and currTree.
    require MerkleTrees.getHash(prevTree, prevNode) == prevRoot();
    require MerkleTrees.getHash(currTree, currNode) == currRoot();

    // No need to make sure that currNode (resp prevNode) is equal to currRoot (resp prevRoot): one can pass an internal node instead.

    // Assume that prevTree and currTree are well-formed.
    MerkleTrees.wellFormedUpTo(currTree, currNode, 3);
    MerkleTrees.wellFormedUpTo(prevTree, prevNode, 3);

    claim(_account, _claimable, _proof);

    assert _claimable == MerkleTrees.getValue(currTree, _account) ||
           _claimable == MerkleTrees.getValue(prevTree, _account);
}
