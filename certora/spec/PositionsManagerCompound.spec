// spec for positions manager .sol

// gives us all of the dispatcher summaries in these files
import "../helpers/erc20.spec"
import "../helpers/compound/specs/PoolToken.spec"
import "../helpers/compound/specs/SymbolicOracle.spec"
import "../helpers/compound/specs/SymbolicComptroller.spec"

// allows us to reference the poolToken in the spec
using DummyPoolTokenA as tokenA // for referencing specific tokens 
using DummyPoolTokenB as tokenB 
using DummyPoolTokenImpl as poolToken // for summarization
using SymbolicOracle as oracle
using SymbolicComptroller as comptroller
using DummyWeth as Weth

methods {
    supplyLogic(address, address, address, uint256, uint256)
    liquidateLogic(address, address, address, uint256)
    borrowLogic(address, uint256, uint256)
    withdrawLogic(address, uint256, address, address, uint256)
    repayLogic(address, address, address, uint256, uint256)

    // rewards manager functions
    accrueUserSupplyUnclaimedRewards(address, address, uint256) => NONDET
    accrueUserBorrowUnclaimedRewards(address, address, uint256) => NONDET

    delegatecall(bytes) => NONDET; // we can't handle this right now, need a workaround

    supplyBalanceInOf(address, address) returns (uint256, uint256) envfree
    borrowBalanceInOf(address, address) returns (uint256, uint256) envfree
    marketStatus(address) returns (bool, bool, bool, bool, bool, bool, bool, bool) envfree

    // whenever the tool encounters mul or div, it will return an arbitrary value that follows the axioms 
    // within the corresponding ghost
    mul(uint256 x, uint256 y) => NONDET // _mul(x, y)
    div(uint256 x, uint256 y) => NONDET // _div(x, y)

    // matching engine functions
    // currently these are summarized to NONDET, so any possible values will be returned
    // it may be better to summarize these with a ghost function or to override the behavior in the harness
    _matchSuppliers(address, uint256, uint256)   returns (uint256, uint256) => NONDET
    _matchBorrowers(address, uint256, uint256)   returns (uint256, uint256) => NONDET 
    _unmatchBorrowers(address, uint256, uint256) returns (uint256)          => NONDET
    _unmatchSuppliers(address, uint256, uint256) returns (uint256)          => NONDET

    // IWETH functions, set to NONDET at the moment but we can change that to the dummy implementation
    withdraw(uint256) => NONDET
    deposit(uint256) => NONDET
    deposit() => NONDET
}

// multiplication and division are very tough for the solver. Since you use the mul and div function, we can try to summarize it
// the ghosts will return a value that follows the axioms below, if you get a counter example that is caused by bs math, adjust the axioms
ghost _mul(uint256, uint256) returns uint256;
// {
//     axiom forall uint256 y1. forall uint256 y2. forall uint256 x1. forall uint256 x2. 
//         (x1 > x2 => _mul(x1, y1) > _mul(x2, y1)) &&
//         (y1 > y2 => _mul(x1, y1) > _mul(x1, y2)) &&
//         ((x1 == 0 || y1 == 0) => _mul(x1,y1) == 0);
// }

ghost _div(uint256, uint256) returns uint256;
// {
    // axiom forall uint256 x1. forall uint256 x2. forall uint256 y1. forall uint256 y2. 
    //     (x1 > x2 => _div(x1, y1) > _div(x2, y1) &&
    //     y1 > y2 => _div(x1, y1) < _div(x1, y2)) ||
    //     y1 == 1 => _div(x1, y1) == x1;
// }

rule sanity(method f)
{
	env e;
	calldataarg args;
	f(e,args);
	assert false;
}

// REVERT CASES

rule supplyAmountZero(address _poolToken, address _supplier, address _onBehalf, uint256 _maxGasForMatching) {
    env e;

    supplyLogic@withrevert(e, _poolToken, _supplier, _onBehalf, 0, _maxGasForMatching);

    assert lastReverted;
}

rule supplyOnBehalfZeroAddress(address _poolToken, address _supplier, uint256 _amount, uint256 _maxGasForMatching) {
    env e;

    supplyLogic@withrevert(e, _poolToken, _supplier, 0, _amount, _maxGasForMatching);

    assert lastReverted;
}

rule supplyUninitializedMarket(address _poolToken, address _supplier, address _onBehalf, uint256 _amount, uint256 _maxGasForMatching) {
    env e; 
    bool isCreated;
    bool isSupplyPaused;
    bool isBorrowPaused;
    bool isWithdrawPaused;
    bool isRepayPaused;
    bool isLiquidateCollateralPaused;
    bool isLiquidateBorrowPaused;
    bool isDeprecated;

    isCreated, isSupplyPaused, isBorrowPaused, isWithdrawPaused, isRepayPaused, isLiquidateCollateralPaused, isLiquidateBorrowPaused, isDeprecated = marketStatus(_poolToken);
    require ! isCreated;

    supplyLogic@withrevert(e, _poolToken, _supplier, _onBehalf, _amount, _maxGasForMatching);

    assert lastReverted;
}

// LIVENESS

rule supplyIncreasesBalance(address _poolToken, address _supplier, address _onBehalf, uint256 _amount, uint256 _maxGasForMatching) {
    env e;
    uint256 inP2P; uint256 onPool;

    require _amount > 0;

    supplyLogic(e, _poolToken, _supplier, _onBehalf, _amount, _maxGasForMatching);

    inP2P, onPool = supplyBalanceInOf(_poolToken, _onBehalf);

    assert inP2P > 0 || onPool > 0;
}
