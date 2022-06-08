-include .env.local
.EXPORT_ALL_VARIABLES:

export PROTOCOL?=compound
export NETWORK?=eth-mainnet
export CHAIN_ID?=1

export FOUNDRY_ETH_RPC_URL?=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}
export FOUNDRY_FORK_BLOCK_NUMBER?=14292587

export DAPP_REMAPPINGS?=@config/=config/${NETWORK}/${PROTOCOL}/

ifeq (${NETWORK}, eth-mainnet)
  export DAPP_REMAPPINGS=@config/=config/${NETWORK}/
endif

ifeq (${NETWORK}, polygon-mainnet)
  export FOUNDRY_FORK_BLOCK_NUMBER=29116728
endif

ifeq (${NETWORK}, avalanche-mainnet)
  export FOUNDRY_FORK_BLOCK_NUMBER=15675271
  export FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
else
endif

ifneq (, $(filter ${NETWORK}, ropsten rinkeby))
  export FOUNDRY_ETH_RPC_URL=https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID}
endif

install: node_modules
	@git submodule update --init --recursive
	@curl -L https://foundry.paradigm.xyz | bash
	@foundryup

deploy: node_modules
	./scripts/deploy.sh

test: node_modules
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz

test-ansi: node_modules
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz > trace.ansi

test-html: node_modules
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz | aha --black > trace.html

fuzz: node_modules
	@echo Running all ${PROTOCOL} fuzzing tests on ${NETWORK}
	@forge test -vv -c test-foundry/fuzzing/${PROTOCOL}

gas-report: node_modules
	@echo Creating gas consumption report for ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL} --gas-report --match-contract TestGasConsumption > gas_report.ansi

test-common: node_modules
	@echo Running all common tests on ${NETWORK}
	@forge test -vvv -c test-foundry/common

contract-% c-%: node_modules
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL}/$*.t.sol --match-contract $*

ansi-c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL}/$*.t.sol --match-contract $* > trace.ansi

html-c-%: node_modules
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL}/$*.t.sol --match-contract $* | aha --black > trace.html

single-% s-%: node_modules
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL} --match-test $*

ansi-s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvvvv -c test-foundry/${PROTOCOL} --match-test $* > trace.ansi

html-s-%: node_modules
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvvvv -c test-foundry/${PROTOCOL} --match-test $* | aha --black > trace.html

config: node_modules
	@forge config

node_modules:
	@yarn

.PHONY: test config common node_modules
