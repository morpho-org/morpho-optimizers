fork-block-number := 22747272

-include .env.local

.PHONY: test
test:  node_modules
	@echo Run all tests
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number $(fork-block-number) -vvv -c test-foundry

single-%: node_modules
	@echo Run single test: $*
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number $(fork-block-number) -vvv -c test-foundry --match-test $*

contract-%: node_modules
	@echo Run tests for $*
	@forge test --fork-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --fork-block-number $(fork-block-number) -vvv -c test-foundry --match-contract $*

node_modules:
	@yarn