-include .env.local
.EXPORT_ALL_VARIABLES:

SMODE?=network
PROTOCOL?=compound
NETWORK?=eth-mainnet

FOUNDRY_SRC=contracts/${PROTOCOL}/
FOUNDRY_TEST=test-foundry/${PROTOCOL}/
FOUNDRY_REMAPPINGS=@config/=config/${NETWORK}/${PROTOCOL}/
FOUNDRY_ETH_RPC_URL?=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}
FOUNDRY_PRIVATE_KEY?=${DEPLOYER_PRIVATE_KEY}

ifeq (${NETWORK}, eth-mainnet)
  FOUNDRY_CHAIN_ID=1
  FOUNDRY_FORK_BLOCK_NUMBER=14292587
endif

ifeq (${NETWORK}, eth-ropsten)
  FOUNDRY_CHAIN_ID=3
endif

ifeq (${NETWORK}, eth-goerli)
  FOUNDRY_CHAIN_ID=5
endif

ifeq (${NETWORK}, polygon-mainnet)
  FOUNDRY_CHAIN_ID=137
  FOUNDRY_FORK_BLOCK_NUMBER=22116728

  ifeq (${PROTOCOL}, aave-v3)
    FOUNDRY_FORK_BLOCK_NUMBER=29116728
    FOUNDRY_CONTRACT_PATTERN_INVERSE=(Fees|IncentivesVault|Rewards)
  endif
endif

ifeq (${NETWORK}, avalanche-mainnet)
  FOUNDRY_CHAIN_ID=43114
  FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
  FOUNDRY_FORK_BLOCK_NUMBER=12675271

  ifeq (${PROTOCOL}, aave-v3)
    FOUNDRY_FORK_BLOCK_NUMBER=15675271
  endif
else
endif

ifeq (${SMODE}, local)
  FOUNDRY_ETH_RPC_URL=http://localhost:8545
endif


install:
	@yarn
	@foundryup
	@git submodule update --init --recursive

	@chmod +x ./scripts/**/*.sh

deploy:
	@echo Deploying Morpho-${PROTOCOL} on ${NETWORK}
	./scripts/${PROTOCOL}/deploy.sh

initialize:
	@echo Initializing Morpho-${PROTOCOL} on ${NETWORK}
	./scripts/${PROTOCOL}/initialize.sh

create-market:
	@echo Creating market on Morpho-${PROTOCOL} on ${NETWORK}
	./scripts/${PROTOCOL}/create-market.sh

anvil:
	@echo Starting fork of ${NETWORK}
	@anvil --fork-url ${FOUNDRY_ETH_RPC_URL}

script-%:
	@echo Running script $* of ${PROTOCOL} on ${NETWORK} with script mode: ${SMODE}
	@forge script scripts/${PROTOCOL}/$*.s.sol:$* --broadcast -vvvv

test:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv | tee trace.ansi

coverage:
	@echo Create coverage report for ${PROTOCOL} tests on ${NETWORK}
	@forge coverage

coverage-lcov:
	@echo Create coverage lcov for ${PROTOCOL} tests on ${NETWORK}
	@forge coverage --report lcov

fuzz:
	$(eval FOUNDRY_TEST=test-foundry/fuzzing/${PROTOCOL}/)
	@echo Running all ${PROTOCOL} fuzzing tests on ${NETWORK}
	@forge test -vv

gas-report:
	@echo Creating gas report for ${PROTOCOL} on ${NETWORK}
	@forge test --gas-report

test-common:
	@echo Running all common tests on ${NETWORK}
	@FOUNDRY_TEST=test-foundry/common forge test -vvv

contract-% c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv --match-contract $* | tee trace.ansi

single-% s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv --match-test $* | tee trace.ansi

storage-layout-generate:
	@./scripts/storage-layout.sh generate snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

storage-layout-check: 
	@./scripts/storage-layout.sh check snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

config:
	@forge config


.PHONY: test config test-common foundry
