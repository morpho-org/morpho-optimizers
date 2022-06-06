-include .env.local

export DAPP_REMAPPINGS=@config/=config/$(NETWORK)/

ifeq (${NETWORK}, avalanche-mainnet)
  export FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
  export FOUNDRY_FORK_BLOCK_NUMBER=15675271
else
  export FOUNDRY_ETH_RPC_URL=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}

  ifeq (${NETWORK}, eth-mainnet)
    export FOUNDRY_FORK_BLOCK_NUMBER=14292587
  else ifeq (${NETWORK}, polygon-mainnet)
    export FOUNDRY_FORK_BLOCK_NUMBER=29116728
    export DAPP_REMAPPINGS=@config/=config/$(NETWORK)/${PROTOCOL}/
  endif
endif

ifeq (${PROTOCOL}, aave-v3)
  export FOUNDRY_SOLC_VERSION=0.8.10
else
  export FOUNDRY_SOLC_VERSION=0.8.13
endif

test:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz

test-ansi:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz > trace.ansi

test-html:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz | aha --black > trace.html

fuzz:
	@echo Running all ${PROTOCOL} fuzzing tests on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vv -c test-foundry/${PROTOCOL} --match-test testFuzz

gas-report:
	@echo Creating gas consumption report for ${PROTOCOL} on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vvv -c test-foundry/${PROTOCOL} --gas-report --match-contract TestGasConsumption > gas_report.ansi

test-common:
	@echo Running all common tests on ${NETWORK}
	@forge test --use solc:0.8.13 -vvv -c test-foundry/common

contract-% c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vvv -c test-foundry/${PROTOCOL} --match-contract $* > trace.ansi

html-c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vvv -c test-foundry/${PROTOCOL} --match-contract $* | aha --black > trace.html

single-% s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vvvvv -c test-foundry/${PROTOCOL} --match-test $* > trace.ansi

html-s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test --use solc:${FOUNDRY_SOLC_VERSION} -vvv -c test-foundry/${PROTOCOL} --match-test $* | aha --black > trace.html

config:
	forge config

.PHONY: test config common
