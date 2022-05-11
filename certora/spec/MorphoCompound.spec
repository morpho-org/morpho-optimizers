import "../helpers/erc20.spec"


using marketsManagerForCompound as markets
using symbolicOracle as oracle
// using SymbolicComptroller as comptroller

methods {
    // // contract methods
    // createMarket(address _poolTokenAddress) returns (uint256[] memory)
    // setNmaxForMatchingEngine(uint16 _newMaxNumber)
    // setThreshold(address _poolTokenAddress, uint256 _newThreshold)

    // function supply(address _poolTokenAddress, uint256 _amount)
    // function borrow(address _poolTokenAddress, uint256 _amount)
    // function withdraw(address _poolTokenAddress, uint256 _amount)
    // function repay(address _poolTokenAddress, uint256 _amount)
    // function liquidate(address _poolTokenBorrowedAddress, address _poolTokenCollateralAddress, address _borrower, uint256 _amount)

    // helper functions from the harness

    // external method summaries
    updateRates(address) => DISPATCHER(true);
    p2pExchangeRate(address) => NONDET;
    isCreated(address) => NONDET; 

    safeTransfer(address, uint256) => DISPATCHER(true);

    getUnderlyingPrice(address) => DISPATCHER(true);
    setUnderlyingPrice(address, uint256) => DISPATCHER(true);

    // comptroller functions used
    // enterMarkets(address[]) => NONDET;
    // closeFactorMantissa() => NONDET;
    // oracle() => NONDET; // set to always oracle needed?
    // liquidationIncentiveMantissa() => NONDET;
    // markets(address) => NONDET;
}

rule sanity(method f) {
    env e;
    calldataarg args;
    f(e, args);
    assert false;
}

// ADD RULES HERE

// invariant a_b()
//     a > b

// invariant relies_on_ab
//     // value
// { preserved {
//     requireInvariant a_b;
// }}