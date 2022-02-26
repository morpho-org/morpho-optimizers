fork-block-number := 24032305

-include .env.local

ifeq (${NETWORK}, avalanche-mainnet)
export FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
else
export FOUNDRY_ETH_RPC_URL=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}
export FOUNDRY_FORK_BLOCK_NUMBER=$(fork-block-number)
endif

export DAPP_REMAPPINGS=@config/=config/$(NETWORK)

.PHONY: test
test: node_modules
	@echo Run all tests
	@forge test -vvv -c test-foundry --no-match-contract TestNmax

contract-% c-%: node_modules
	@echo Run tests for contract $*
	@forge test -vvv -c test-foundry --match-contract $*

single-% s-%: node_modules
	@echo Run single test: $*
	@forge test -vvv -c test-foundry --match-test $*

node_modules:
	@yarn