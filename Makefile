-include .env.local
.EXPORT_ALL_VARIABLES:

SMODE?=network
PROTOCOL?=compound
NETWORK?=eth-mainnet

FOUNDRY_SRC=contracts/${PROTOCOL}/
FOUNDRY_TEST=test-foundry/${PROTOCOL}/
FOUNDRY_REMAPPINGS=@config/=config/${NETWORK}/${PROTOCOL}/

FOUNDRY_PRIVATE_KEY?=${DEPLOYER_PRIVATE_KEY}

ifdef FOUNDRY_ETH_RPC_URL
  FOUNDRY_TEST=test-foundry/prod/${PROTOCOL}/
  FOUNDRY_FUZZ_RUNS=4096
  FOUNDRY_FUZZ_MAX_LOCAL_REJECTS=16384
  FOUNDRY_FUZZ_MAX_GLOBAL_REJECTS=1048576
else
  ifeq (${NETWORK}, avalanche-mainnet)
    FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
  endif
  
  FOUNDRY_ETH_RPC_URL=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}
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
	@echo Initializing Morpho-${PROTOCOL} on "${NETWORK}"
	./scripts/${PROTOCOL}/initialize.sh

create-market:
	@echo Creating market on Morpho-${PROTOCOL} on "${NETWORK}"
	./scripts/${PROTOCOL}/create-market.sh

anvil:
	@echo Starting fork of "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}"
	@anvil --fork-url ${FOUNDRY_ETH_RPC_URL} --fork-block-number "${FOUNDRY_FORK_BLOCK_NUMBER}"

script-%:
	@echo Running script $* of Morpho-${PROTOCOL} on "${NETWORK}" with script mode: ${SMODE}
	@forge script scripts/${PROTOCOL}/$*.s.sol:$* --broadcast -vvvv

test:
	@echo Running all Morpho-${PROTOCOL} tests on "${NETWORK}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test -vv | tee trace.ansi

test-no-rewards:
	@echo Running all Morpho-${PROTOCOL} tests on "${NETWORK}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test -vv --no-match-contract "Fees|IncentivesVault|Rewards" | tee trace.ansi

coverage:
	@echo Create coverage report for Morpho-${PROTOCOL} tests on "${NETWORK}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge coverage

coverage-lcov:
	@echo Create coverage lcov for Morpho-${PROTOCOL} tests on "${NETWORK}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge coverage --report lcov

fuzz:
	$(eval FOUNDRY_TEST=test-foundry/fuzzing/${PROTOCOL}/)
	@echo Running all Morpho-${PROTOCOL} fuzzing tests on "${NETWORK}" at with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test -vv

gas-report:
	@echo Creating gas report for Morpho-${PROTOCOL} on "${NETWORK}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test --gas-report

test-common:
	@echo Running all common tests on "${NETWORK}"
	@FOUNDRY_TEST=test-foundry/common forge test -vvv

contract-% c-%:
	@echo Running tests for contract $* of Morpho-${PROTOCOL} on "${NETWORK}"
	@forge test -vvv --match-contract $* | tee trace.ansi

single-% s-%:
	@echo Running single test $* of Morpho-${PROTOCOL} on "${NETWORK}"
	@forge test -vvv --match-test $* | tee trace.ansi

storage-layout-generate:
	@./scripts/storage-layout.sh generate snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

storage-layout-check:
	@./scripts/storage-layout.sh check snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

config:
	@forge config


.PHONY: test config test-common foundry
