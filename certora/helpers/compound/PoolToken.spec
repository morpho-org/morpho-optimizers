// pool token spec
// the purpose of this spec is for summarization of the poolToken or anything else specific to it
// we do this to keep specs clean of less important information

using DummyPoolTokenImpl as cToken

methods {
    accrueInterest()                            returns (uint256)       envfree => DISPATCHER(true)
    borrowRate()                                returns (uint256)       envfree => DISPATCHER(true)
    borrowIndex()                               returns (uint256)       envfree => DISPATCHER(true)
    borrowBalanceStored(address)                returns (uint256)       envfree => DISPATCHER(true)
    mint(uint256)                               returns (uint256)               => DISPATCHER(true)
    exchangeRateCurrent()                       returns (uint256)               => DISPATCHER(true)
    exchangeRateStored()                        returns (uint256)       envfree => DISPATCHER(true)
    supplyRatePerBlock()                        returns (uint256)       envfree => DISPATCHER(true)
    redeem(uint256)                             returns (uint256)               => DISPATCHER(true)
    redeemUnderlying(uint256)                   returns (uint256)               => DISPATCHER(true)
    // transferFrom(address, address, uint256)     returns (bool)                  => DISPATCHER(true)
    // transfer(address, uint256)                  returns (bool)                  => DISPATCHER(true)
    // balanceOf(address)                          returns (uint256)       envfree => DISPATCHER(true)
    balanceOfUnderlying(address)                returns (uint256)       envfree => DISPATCHER(true)
    borrow(uint256)                             returns (uint256)               => DISPATCHER(true)
    borrowRatePerBlock()                        returns (uint256)       envfree => DISPATCHER(true)
    borrowBalanceCurrent(address)               returns (uint256)       envfree => DISPATCHER(true)
    repayBorrow(uint256)                        returns (uint256)               => DISPATCHER(true)
    underlying()                                returns (address)       envfree => DISPATCHER(true)
    supply()                                    returns (uint256)       envfree => DISPATCHER(true)
}