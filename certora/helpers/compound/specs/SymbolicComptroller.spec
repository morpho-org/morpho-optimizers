methods {
    getAssetsIn(address)                                                        returns (address[])                 envfree => DISPATCHER(true)
    checkMembership(address, address)                                           returns (bool)                      envfree => DISPATCHER(true)
    enterMarkets(address[])                                                     returns (uint256[])                 envfree => DISPATCHER(true)
    exitMarket(address)                                                         returns (uint256)                   envfree => DISPATCHER(true)
    mintAllowed(address, address, uint256)                                      returns (uint256)                   envfree => DISPATCHER(true)
    mintVerify(address, address, uint256, uint256)                                                                  envfree => DISPATCHER(true)
    redeemAllowed(address, address, uint256)                                    returns (uint256)                   envfree => DISPATCHER(true)
    redeemVerify(address, address, uint256, uint256)                                                                envfree => DISPATCHER(true)
    borrowAllowed(address, address, uint256)                                    returns (uint256)                   envfree => DISPATCHER(true)
    borrowVerify(address, address, uint256)                                                                         envfree => DISPATCHER(true)
    repayBorrowAllowed(address, address, address, uint256)                      returns (uint256)                   envfree => DISPATCHER(true)
    repayBorrowVerify(address, address, address, uint256, uint256)                                                  envfree => DISPATCHER(true)
    liquidateBorrowAllowed(address, address, address, address, uint256)         returns (uint256)                   envfree => DISPATCHER(true)
    liquidateBorrowVerify(address, address, address, address, uint256, uint256)                                     envfree => DISPATCHER(true)
    seizeAllowed(address, address, address, address, uint256)                   returns (uint256)                   envfree => DISPATCHER(true)
    seizeVerify(address, address, address, address, uint256)                                                        envfree => DISPATCHER(true)
    transferAllowed(address, address, address, uint256)                         returns (uint256)                   envfree => DISPATCHER(true)
    transferVerify(address, address, address, uint256)                                                              envfree => DISPATCHER(true)
    liquidateCalculateSeizeTokens(address, address, uint256)                    returns (uint256, uint256)          envfree => DISPATCHER(true)
    getAccountLiquidity(address)                                                returns (uint256, uint256, uint256) envfree => DISPATCHER(true)
    getHypotheticalAccountLiquidity(address, address, uint256, uint256)         returns (uint256, uint256, uint256) envfree => DISPATCHER(true)
}