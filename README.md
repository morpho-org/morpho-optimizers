# leech-contracts

This is the repo where all the Leech contracts are.

## Installation

### Dependancies

- Truffle (developpement environement to compile and migrate solidity)
    - With yarn (recommanded) : `yarn global add ganache-cli`
    - With npm : `npm install -g truffle`

- Ganache CLI (local Ethereum blockchain for development)
    - With yarn (recommanded) : `yarn global add ganache-cli`
    - With npm : `npm install -g ganache-cli`

- uniswap-lib (solidity libraries shared across Uniswap contracts)
    - With yarn (recommanded) : `yarn add @uniswap/lib`
    - With npm : `npm install @uniswap/lib`

### Creation of the local Ethereum fork

- You have to :
    - Fork the Ethereum mainnet 
    - unlock an address 
    - choose one port 
    - use 10 default address given by this specfic accounts used for testing 
    - identifier the network as 1 
    - the address of Dai Join unlocked to mint some DAI. 
    If you want to mint some token then add the cTokenMainnetAddress and use the scripts in scripts/seed-account-with-erc20/
    - ```ganache-cli --fork https://mainnet.infura.io/v3/YOUR_KEY_HERE -m "candy captain shoe salt awake harvest setup primary inmate ugly among become"  -i 1 -p 7545 -u 0x9759A6Ac90977b93B58547b4A71c78317f391A28 0xb3319f5d18bc0d84dd1b4825dcde5d5f7266d407```

### Compile and migrate the contracts to the blockchain

- Compile the contracts (optionnal)
    - `truffle compile`

- Deploy contract on Ganache
    - `truffle migrate --reset`

## Scripts

We made some scripts to make your life easier. It is hardcoded for DAI/cDAI but could be any Erc20 token that is supported on Comp.

- Mint DAI for main account : `node scripts/seed-account-with-erc20/dai.js `
- Supply DAI on Compound : `node scripts/supplyErc20ToCompound.js`
- Supply DAI, get cDAI, redeem cDAI, get DAI back : `node scripts/supplyAndRedeemErc20ToCompound.js`

## Debugging tools

- Use the truffle console : `truffle console`
    - Get an account eth balance 
        ```let balance = await web3.eth.getBalance("0xa0df350d2637096571F7A701CBc1C5fdE30dF76A")
        console.log('eth balance of the account: ', balance)```

    - Get Leech CEth balance : 
        ```const cEthJson = require('./abis/CEth.json')
        const compoundModuleJson = require('./abis/CompoundModule.json')
        const compoundModuleContractAddress = compoundModuleJson.networks[1].address
        let cEthContractAddress = '0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5'
        const cEthContract = new web3.eth.Contract(cEthJson.abi, cEthContractAddress)
        let leechCEthBalance = await cEthContract.methods.balanceOf(compoundModuleContractAddress).call()
        console.log("Leech ceth balance",leechCEthBalance.toString())```

    - Get Leech Lending Balance : 
        ```const compoundModuleJson = require('./abis/CompoundModule.json')
        const compoundModuleContractAddress = compoundModuleJson.networks[1].address
        const compoundModuleContract = new web3.eth.Contract(compoundModuleJson.abi, compoundModuleContractAddress)
        let lendingBalance = await compoundModuleContract.methods.lendingBalanceOf('0xb94268c327a1D07f43B592263559200c6AC56062').call()
        console.log("Leech lending balance",lendingBalance.used.toString())```