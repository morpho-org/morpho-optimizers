using MerkleTree1 as T1
using MerkleTree2 as T2

methods {
    prevRoot() returns bytes32 envfree
    currRoot() returns bytes32 envfree
    claim(address, uint256, bytes32[]) envfree
    T1.root() returns address envfree
    T1.hash(address) returns bytes32 envfree
    T1.isValid() returns bool envfree
    T1.value(address) returns uint256 envfree
    T2.root() returns address envfree
    T2.hash(address) returns bytes32 envfree
    T2.isValid() returns bool envfree
    T2.value(address) returns uint256 envfree
}

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;  uint256 claimed;

    require (claimed <= _claimable);

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, claimed, _proof);

    assert lastReverted;
}

rule claimOnlyValue(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;
    require T1.hash(T1.root()) == prevRoot() && T2.hash(T2.root()) == currRoot();

    claim(_account, _claimable, _proof);

    assert _claimable == T1.value(_account) || _claimable == T2.value(_account);
}

// rule claimOnlyValue(address _account, uint256 _claimable, bytes32[] _proof) {
//     env e; Tree t;
//     require M.isValidTree(t);
//     require _claimable == M.value(t, _account);

//     bytes32[] proof = findProof(t, _account, _claimable);

//     claim(_account, _claimable, proof);
// }

// rule claimRevertConditions() {}

// rule claimLessThanMax() {}
