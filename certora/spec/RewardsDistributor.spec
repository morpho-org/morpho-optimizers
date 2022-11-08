methods {
    function claim(address, uint256, bytes32[]) envfree
}

rule noMultipleDistribute(address _account, bytes32[] _proof) {
    env e; 

    claim(_account, _proof);

    claim@withrevert(_account, _proof);

    assert lastReverted;
}

