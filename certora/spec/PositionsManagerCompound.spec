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

methods {

}

rule sanity(method f)
{
	env e;
	calldataarg args;
	f(e,args);
	assert false;
}
