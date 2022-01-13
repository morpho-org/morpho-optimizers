
-include .env.local

TESTS = \
	TestBorrow \
	TestGovernance \
	TestLiquidate \
	TestRepay \
	TestSupply \
	TestWithdraw

test:
	@echo Run all tests
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number 22747272 -vvv

test1:
	@echo Run test matching regexp
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number 22747272 -vvv --match-test test_liquidate_5_1

$(TESTS):
	@echo Run tests for $@
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number 22747272 -vvv --match-contract $@
