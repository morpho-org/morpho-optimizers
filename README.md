# leech-contracts
### Fork Ethereum to use Compound

- Fork the Ethereum mainnet + unlock an address + choose one port + use 10 default address given by this specfic accounts used for testing + identifier the network as 1 + the address of Dai Join unlocked to mint some DAI. If you want to mint some token then add the cTokenMainnetAddress and use the scripts in scripts/seed-account-with-erc20/
    - `ganache-cli --fork https://mainnet.infura.io/v3/YOUR_KEY_HERE -m "candy captain shoe salt awake harvest setup primary inmate ugly among become"  -i 1 -p 7545 -u 0x9759A6Ac90977b93B58547b4A71c78317f391A28 0xb3319f5d18bc0d84dd1b4825dcde5d5f7266d407`

### Then

- Deploy contract on Ganache
    - `truffle migrate --reset`

- Run the NodeJS server
    - `npm start`


### Scripts (DAI/cDAI hardcoded but could be any Erc20 token that is supported on Comp)

- Mint DAI for main account : `node scripts/seed-account-with-erc20/dai.js `
- Supply DAI, get cDAI, redeem cDAI, get DAI back : `node scripts/supplyAndRedeemErc20ToCompound.js`
- Supply DAI only : `node scripts/supplyErc20ToCompound.js`

### Debugging tools

- Use the truffle console : `truffle console`
    - Get an account eth balance 
        `let balance = await web3.eth.getBalance("0xa0df350d2637096571F7A701CBc1C5fdE30dF76A")` 
        `console.log('eth balance of the account: ', balance)`

    - Get Leech CEth balance : 
        const cEthJson = require('./abis/CEth.json')
        const compoundModuleJson = require('./abis/CompoundModule.json')
        const compoundModuleContractAddress = compoundModuleJson.networks[1].address
        let cEthContractAddress = '0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5'
        const cEthContract = new web3.eth.Contract(cEthJson.abi, cEthContractAddress)
        let leechCEthBalance = await cEthContract.methods.balanceOf(compoundModuleContractAddress).call()
        console.log("Leech ceth balance",leechCEthBalance.toString())
    - Get Leech Lending Balance : 
        const compoundModuleJson = require('./abis/CompoundModule.json')
        const compoundModuleContractAddress = compoundModuleJson.networks[1].address
        const compoundModuleContract = new web3.eth.Contract(compoundModuleJson.abi, compoundModuleContractAddress)
        let lendingBalance = await compoundModuleContract.methods.lendingBalanceOf('0xb94268c327a1D07f43B592263559200c6AC56062').call()
        console.log("Leech lending balance",lendingBalance.used.toString())