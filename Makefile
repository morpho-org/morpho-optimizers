fork-block-number := 22747272

-include .env.local

TESTS = \
	TestBorrow \
	TestGovernance \
	TestLiquidate \
	TestRepay \
	TestSupply \
	TestWithdraw \
	TestDoubleLinkedList \
	TestNmax \
	TestGetters \
	TestFees


.PHONY: test
test: node_modules
	@echo Run all tests
	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv -c test-foundry --no-match-contract TestNmax


.PHONY: test1
test1: node_modules
	@echo Run test matching regexp
	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv -c test-foundry --match-contract TestMarketStrategy


.PHONY: testNmax
testNmax: node_modules
	@echo Run test matching regexp
	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvvvv -c test-foundry --match-contract TestNmax


.PHONY: $(TESTS)
$(TESTS): node_modules
	@echo Run tests for $@
	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv --match-contract $@

node_modules:
	@yarn