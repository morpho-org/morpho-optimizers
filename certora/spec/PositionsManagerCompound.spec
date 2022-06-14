// spec for positions manager .sol

// gives us all of the dispatcher summaries in these files
import "../helpers/erc20.spec"
import "../helpers/compound/PoolToken.spec"
import "../helpers/compound/SymbolicOracle.spec"

// allows us to reference the poolToken in the spec
using DummyPoolTokenA as tokenA // for referencing specific tokens 
using DummyPoolTokenB as tokenB 
using DummyPoolTokenImpl as poolToken // for summarization
using SymbolicOracle as oracle
using SymbolicComptroller as comptroller

methods {
    // external functions of the contract
    supplyLogic(address, address, address, uint256, uint256)
    liquidateLogic(address, address, address, uint256)
    borrowLogic(address, uint256, uint256)
    withdrawLogic(address, uint256, address, address, uint256)
    repayLogic(address, address, address, uint256, uint256)

    // summarized these IWETH functions as NONDET until a better solution is made
    deposit() => NONDET;
    withdraw(uint256) => NONDET;

    // summarization of comptroller functions used. The symbolic is included so it will dispatch to it
    // closeFactorMantissa() => DISPATCHER(true);
    // liquidationIncentiveMantissa() => DISPATCHER(true);
    // oracle() => DISPATCHER(true);
    // markets(address) returns (comptroller.Market) => DISPATCHER(true);

    // rewards manager functions
    accrueUserSupplyUnclaimedRewards(address, address, uint256) => NONDET; // inline the function
    accrueUserBorrowUnclaimedRewards(address, address, uint256) => NONDET;

    delegatecall(bytes) => NONDET; // we can't handle this right now, need a workaround

    // functions we are summarizing
    // whenever the tool encounters mul or div, it will return an arbitrary value that follows the axioms 
    // within the corresponding ghost
    mul(uint256 x, uint256 y) => _mul(x, y);
    div(uint256 x, uint256 y) => _div(x, y);
}

// multiplication and division are very tough for the solver. Since you use the mul and div function, we can try to summarize it
// the ghosts will return a value that follows the axioms below, if you get a counter example that is caused by bs math, adjust the axioms
ghost _mul(uint256, uint256) returns uint256 {
    axiom forall uint256 y. forall uint256 x1. forall uint256 x2. x1 > x2 => _mul(x1, y) > _mul(x2, y); // will increase as values increase
    axiom forall uint256 y1. forall uint256 y2. forall uint256 x. y1 > y2 => _mul(x, y1) > _mul(x, y2);
    axiom forall uint256 x. forall uint256 y. x == 0 || y == 0 => _mul(x,y) == 0; // case of zero
}

ghost _div(uint256, uint256) returns uint256 {
    axiom forall uint256 x1. forall uint256 x2. forall uint256 y. x1 > x2 => _div(x1, y) < _div(x2, y); // decrease as values increase
    axiom forall uint256 y1. forall uint256 y2. forall uint256 x. y1 > y2 => _div(x, y1) < _div(x, y2); 
}


rule sanity(method f)
{
	env e;
	calldataarg args;
	f(e,args);
	assert false;
}
