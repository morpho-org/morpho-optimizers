fork-block-number := 24032305

-include .env.local

export FOUNDRY_ETH_RPC_URL=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}
export FOUNDRY_FORK_BLOCK_NUMBER=$(fork-block-number)

.PHONY: test
test: node_modules
	@echo Run all tests
	@forge test --no-match-contract TestNmax

contract-% c-%: node_modules
	@echo Run tests for contract $*
	@forge test --match-contract $*

single-% s-%: node_modules
	@echo Run single test: $*
	@forge test --match-test $*

node_modules:
	@yarn