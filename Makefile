fork-block-number := 22747272

-include .env.local

TESTS = \
	TestBorrow \
	TestGovernance \
	TestLiquidate \
	TestRepay \
	TestSupply \
	TestWithdraw \
	TestDoubleLinkedList


.PHONY: test
test:  node_modules
	@echo Run all tests
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number $(fork-block-number) -vvv -c test-foundry

.PHONY: test1
test1: node_modules
	@echo Run test matching regexp
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number $(fork-block-number) -vvv --match-test test_borrow_2_2

.PHONY: $(TESTS)
$(TESTS): node_modules
	@echo Run tests for $@
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number $(fork-block-number) -vvv --match-contract $@

node_modules:
	@yarn