// spec for positions manager .sol

methods {

}

rule sanity(method f)
{
	env e;
	calldataarg args;
	f(e,args);
	assert false;
}
