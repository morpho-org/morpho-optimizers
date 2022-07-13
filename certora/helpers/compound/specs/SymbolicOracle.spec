methods {
        underlyingPrice(address)                        returns (uint256)
        unclaimedRewards(address, address)              returns (uint256)
        getUnderlyingPrice(address)                     returns (uint256)       envfree => DISPATCHER(true)
        setUnderlyingPrice(address, uint256)                                    envfree => DISPATCHER(true)
        accrueUserUnclaimedRewards(address[], address)  returns (uint256)       envfree => DISPATCHER(true)
}