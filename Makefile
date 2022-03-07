fork-block-number := 24032305

-include .env.local

.PHONY: test
test: node_modules
	@echo Run all tests
	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv -c test-foundry --no-match-contract TestNmax

contract-% c-%: node_modules
	@echo Run tests for contract $*
	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvvv -c test-foundry --match-contract $*

single-% s-%: node_modules
	@echo Run single test: $*
	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv -c test-foundry --match-test $*

node_modules:
	@yarn