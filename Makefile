
-include .env.local

export NETWORK

solc		:; nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_8_7
all    	:; dapp build
clean  	:; dapp clean
test   	:; dapp test --rpc-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --rpc-block 22747272
test1		:; dapp test --rpc-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --rpc-block 22747272 -m testSupply_1_6
testSupply		:; dapp test --rpc-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --rpc-block 22747272 -m Supply
testBorrow		:; dapp test --rpc-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --rpc-block 22747272 -m Borrow
testWithdraw		:; dapp test --rpc-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --rpc-block 22747272 -m Withdraw
testRepay		:; dapp test --rpc-url https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID} --rpc-block 22747272 -m Repay
#deploy 	:; dapp create Dapptuto
