rule getter_never_reverts(method getter)
filtered { getter -> getter.isView }
{
	env e;
	require e.msg.value == 0;
	calldataarg arg;
	getter@withrevert(e,arg);
	assert !lastReverted, "getter reverts";
}

rule affectsGetters(method getter, method f)
filtered { getter -> getter.isView, f -> !f.isView }
{
	env e;
	calldataarg argGetter;
	// restrict to getters that return a uint256?
	uint pre = getter(e, argGetter);

	calldataarg argChange;
	f(e, argChange);

	uint post = getter(e, argGetter);
	assert pre == post, "${f} affects result of ${getter}";
}
