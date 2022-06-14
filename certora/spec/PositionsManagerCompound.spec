// spec for positions manager .sol

// allows us to reference the poolToken in the spec
using DummyPoolTokenA as tokenA // for referencing specific tokens 
using DummyPoolTokenB as tokenB 
using DummyPoolTokenImpl as poolToken // for summarization

methods {

}

rule sanity(method f)
{
	env e;
	calldataarg args;
	f(e,args);
	assert false;
}
