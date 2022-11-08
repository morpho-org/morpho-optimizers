methods {
    claim(address, uint256, bytes32[]) envfree
}

rule noMultipleDistribute(address _account, uint256 _claimable, bytes32[] _proof) {
    env e; 

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, _claimable, _proof);

    assert lastReverted;
}

