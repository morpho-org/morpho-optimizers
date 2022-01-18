.PHONY: test

-include .env.local

TESTS = \
	TestBorrow \
	TestGovernance \
	TestLiquidate \
	TestRepay \
	TestSupply \
	TestWithdraw \
	TestDoubleLinkedList

test:
	@echo Run all tests
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number 22747272 -vvv

test1:
	@echo Run test matching regexp
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number 22747272 -vvvvv --match-test test_withdraw_3_3_2

$(TESTS):
	@echo Run tests for $@
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number 22747272 -vvv --match-contract $@
