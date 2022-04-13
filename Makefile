-include .env.local

ifeq (${NETWORK}, avalanche-mainnet)
  export FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
  export FOUNDRY_FORK_BLOCK_NUMBER=9833154
else
  export FOUNDRY_ETH_RPC_URL=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}

  ifeq (${NETWORK}, eth-mainnet)
    export FOUNDRY_FORK_BLOCK_NUMBER=14292587
  else ifeq (${NETWORK}, polygon-mainnet)
    export FOUNDRY_FORK_BLOCK_NUMBER=24032305
  endif
endif

export DAPP_REMAPPINGS=@config/=config/$(NETWORK)

.PHONY: test
test: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test -vv -c test-foundry --no-match-contract TestGasConsumption

gas:
	@echo Create report
	@forge test -vvv -c test-foundry --gas-report --match-test testGasConsumptionOfMatchBorrowers > gas_report.ansi

contract-% c-%: node_modules
	@echo Run tests for contract $* on ${NETWORK}
	@forge test -vvv -c test-foundry --match-contract $*

single-% s-%: node_modules
	@echo Run single test $* on ${NETWORK}
	@forge test -vvv -c test-foundry --match-test $* > trace.ansi

.PHONY: config
config:
	forge config

node_modules:
	@yarn
