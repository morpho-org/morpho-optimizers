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
  FOUNDRY_ETH_RPC_URL=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}

  ifeq (${NETWORK}, eth-mainnet)
    FOUNDRY_CHAIN_ID=1
    FOUNDRY_FORK_BLOCK_NUMBER?=14292587
  endif

  ifeq (${NETWORK}, eth-ropsten)
    FOUNDRY_CHAIN_ID=3
  endif

  ifeq (${NETWORK}, eth-goerli)
    FOUNDRY_CHAIN_ID=5
  endif

  ifeq (${NETWORK}, polygon-mainnet)
    ifeq (${PROTOCOL}, aave-v3)
      FOUNDRY_FORK_BLOCK_NUMBER?=29116728
      FOUNDRY_CONTRACT_PATTERN_INVERSE=(Fees|IncentivesVault|Rewards)
    endif

    FOUNDRY_CHAIN_ID=137
    FOUNDRY_FORK_BLOCK_NUMBER?=22116728
  endif

  ifeq (${NETWORK}, avalanche-mainnet)
    ifeq (${PROTOCOL}, aave-v3)
      FOUNDRY_FORK_BLOCK_NUMBER?=15675271
    endif

    FOUNDRY_CHAIN_ID=43114
    FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
    FOUNDRY_FORK_BLOCK_NUMBER?=12675271
  endif
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
	@echo Running all Morpho-${PROTOCOL} tests on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test -vv

coverage:
	@echo Create lcov coverage report for Morpho-${PROTOCOL} tests on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge coverage --report lcov
	@lcov --remove lcov.info -o lcov.info "test-foundry/*"

lcov-html:
	@echo Transforming the lcov coverage report into html
	@genhtml lcov.info -o coverage

fuzz:
	$(eval FOUNDRY_TEST=test-foundry/fuzzing/${PROTOCOL}/)
	@echo Running all Morpho-${PROTOCOL} fuzzing tests on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test -vv

gas-report:
	@echo Creating gas report for Morpho-${PROTOCOL} on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test --gas-report

test-common:
	@echo Running all common tests on "${NETWORK}"
	@FOUNDRY_TEST=test-foundry/common forge test -vvv

contract-% c-%:
	@echo Running tests for contract $* of Morpho-${PROTOCOL} on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}"
	@forge test -vvv --match-contract $*

single-% s-%:
	@echo Running single test $* of Morpho-${PROTOCOL} on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}"
	@forge test -vvvv --match-test $*

storage-layout-generate:
	@./scripts/storage-layout.sh generate snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

storage-layout-check:
	@./scripts/storage-layout.sh check snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

config:
	@forge config


.PHONY: test config test-common foundry coverage
