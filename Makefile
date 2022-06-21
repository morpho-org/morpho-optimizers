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

install:
	@yarn
	@foundryup
	@git submodule update --init --recursive

	@chmod +x ./scripts/**/*.sh

deploy:
	./scripts/${PROTOCOL}/deploy.sh

initialize:
	./scripts/${PROTOCOL}/initialize.sh

create-market:
	./scripts/create-market.sh

test:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz

test-ansi:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz > trace.ansi

test-html:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv -c test-foundry/${PROTOCOL} --no-match-contract TestGasConsumption --no-match-test testFuzz | aha --black > trace.html

fuzz:
	@echo Running all ${PROTOCOL} fuzzing tests on ${NETWORK}
	@forge test -vv -c test-foundry/fuzzing/${PROTOCOL}

gas-report:
	@echo Creating gas consumption report for ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL} --gas-report --match-contract TestGasConsumption > gas_report.ansi

test-common:
	@echo Running all common tests on ${NETWORK}
	@forge test -vvv -c test-foundry/common

contract-% c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL}/$*.t.sol --match-contract $*

ansi-c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL}/$*.t.sol --match-contract $* > trace.ansi

html-c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL}/$*.t.sol --match-contract $* | aha --black > trace.html

single-% s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv -c test-foundry/${PROTOCOL} --match-test $*

ansi-s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvvvv -c test-foundry/${PROTOCOL} --match-test $* > trace.ansi

html-s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvvvv -c test-foundry/${PROTOCOL} --match-test $* | aha --black > trace.html

config:
	@forge config


.PHONY: test config common foundry
