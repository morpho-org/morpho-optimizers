using MerkleTree1 as T1
using MerkleTree2 as T2

using MorphoToken as MorphoToken

methods {
    MORPHO() returns address envfree
    currRoot() returns bytes32 envfree
    claimed(address) returns uint256 envfree
    claim(address, uint256, bytes32[]) envfree => DISPATCHER(true)
    claimOne(address, uint256, bytes32) envfree
    transfer(address, uint256) => DISPATCHER(true)

    T1.initialized() returns bool envfree
    T1.newAccount(address, uint256) envfree
    T1.newNode(address, address, address) envfree
    T1.setRoot(address) envfree
    T1.isWellFormed(address) returns bool envfree
    T1.findProof(address) returns bytes32[] envfree
    T1.getRoot() returns address envfree
    T1.getCreated(address) returns bool envfree
    T1.getLeft(address) returns address envfree
    T1.getRight(address) returns address envfree
    T1.getValue(address) returns uint256 envfree
    T1.getHash(address) returns bytes32 envfree
    T1.findAndClaimAt(address, address) envfree

    T2.initialized() returns bool envfree
    T2.newAccount(address, uint256) envfree
    T2.newNode(address, address, address) envfree
    T2.setRoot(address) envfree
    T2.isWellFormed(address) returns bool envfree
    T2.findProof(address) returns bytes32[] envfree
    T2.getRoot() returns address envfree
    T2.getCreated(address) returns bool envfree
    T2.getLeft(address) returns address envfree
    T2.getRight(address) returns address envfree
    T2.getValue(address) returns uint256 envfree
    T2.getHash(address) returns bytes32 envfree
    T2.findAndClaimAt(address, address) envfree

    keccak(address, uint256) envfree
    checkHash(address, uint256, bytes32) envfree

    MorphoToken.balanceOf(address) returns uint256 envfree
}

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;  uint256 claimed;

    require (claimed <= _claimable);

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, claimed, _proof);

    assert lastReverted;
}

rule checkOneHash(address _account, uint256 _claimable, bytes32 _proof) {
    checkHash(_account, _claimable, _proof);

    assert keccak(to_bytes32(to_bytes20(_account)), to_bytes32(_claimable)) == _proof;
}
