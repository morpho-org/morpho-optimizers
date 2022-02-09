
-include .env.local

export NETWORK

solc :; nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_8_7
all :; dapp build
clean :; dapp clean
.PHONY: test
test :; dapp test --rpc-url  https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --rpc-block 24032305 
test1 :; dapp test --rpc-url  https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --rpc-block 24032305 -m test_withdraw_3_3_4


# fork-block-number := 24032305

# -include .env.local

# .PHONY: test
# test: node_modules
# 	@echo Run all tests
# 	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv -c test-foundry --no-match-contract TestNmax

# contract-% c-%: node_modules
# 	@echo Run tests for contract $*
# 	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv -c test-foundry --match-contract $*

# single-% s-%: node_modules
# 	@echo Run single test: $*
# 	@forge test --fork-url https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY} --fork-block-number $(fork-block-number) -vvv -c test-foundry --match-test $*

# node_modules:
# 	@yarn