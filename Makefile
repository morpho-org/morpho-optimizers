-include .env.local

ifeq (${NETWORK}, avalanche-mainnet)
  export FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
  export FOUNDRY_FORK_BLOCK_NUMBER=9833154
else
  export FOUNDRY_ETH_RPC_URL=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}

  ifeq (${NETWORK}, eth-mainnet)
    export FOUNDRY_FORK_BLOCK_NUMBER=14292587
  else ifeq (${NETWORK}, polygon-mainnet)
    export FOUNDRY_FORK_BLOCK_NUMBER=29116728
  endif
endif

export DAPP_REMAPPINGS=@config/=config/$(NETWORK)/aave-v3/

.PHONY: test
ci-aave: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test -vv -c test-foundry/aave-v2 --no-match-contract TestGasConsumption --no-match-test testFuzz

.PHONY: test
ci-compound: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test -vv -c test-foundry/aave-v2 --no-match-contract TestGasConsumption --no-match-test testFuzz

test-aave-v2: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test -vv -c test-foundry/aave-v3 --no-match-contract TestGasConsumption --no-match-test testFuzz

test-aave-v3: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test --use solc:0.8.10 -vv -c test-foundry/aave-v3 --no-match-contract TestGasConsumption --no-match-test testFuzz

withdraw: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test --use solc:0.8.10 -vv -c test-foundry/aave-v3 --match-test testDeltaWithdraw

repay: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test --use solc:0.8.10 -vv -c test-foundry/aave-v3 --match-test testDeltaRepay

test-aave-v2: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test --use solc:0.8.13 -vv -c test-foundry/aave-v2 --no-match-contract TestGasConsumption --no-match-test testFuzz

test-compound: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test --use solc:0.8.13 -vv -c test-foundry/compound --no-match-contract TestGasConsumption --no-match-test testFuzz

test-compound-ansi: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test --use solc:0.8.13 -vv -c test-foundry/compound --no-match-contract TestGasConsumption --no-match-test testFuzz > trace.ansi

test-compound-html: node_modules
	@echo Run all tests on ${NETWORK}
	@forge test --use solc:0.8.13 -vv -c test-foundry/compound --no-match-contract TestGasConsumption --no-match-test testFuzz | aha --black > trace.html

fuzz-compound: node_modules
	@echo Run all fuzzing tests on ${NETWORK}
	@forge test --use solc:0.8.13 -vv -c test-foundry/compound --match-test testFuzz

gas-report-compound:
	@echo Create report
	@forge test --use solc:0.8.13 -vvv -c test-foundry/compound --gas-report --match-contract TestGasConsumption > gas_report.ansi

common:
	@echo Run all common tests
	@forge test --use solc:0.8.13 -vvv -c test-foundry/common

contract-% c-%: node_modules
	@echo Run tests for contract $* on ${NETWORK}
	@forge test --use solc:0.8.10 -vvv -c test-foundry/compound --match-contract $* > trace.ansi

html-c-%: node_modules
	@echo Run tests for contract $* on ${NETWORK}
	@forge test --use solc:0.8.10 -vvv -c test-foundry/compound --match-contract $* | aha --black > trace.html

single-% s-%: node_modules
	@echo Run single test $* on ${NETWORK}
	@forge test --use solc:0.8.10 -vv -c test-foundry/aave-v3 --match-test $*

html-s-%: node_modules
	@echo Run single test $* on ${NETWORK}
	@forge test --use solc:0.8.10 -vvv -c test-foundry/compound --match-test $* | aha --black > trace.html

.PHONY: config
config:
	forge config

node_modules:
	@yarn
