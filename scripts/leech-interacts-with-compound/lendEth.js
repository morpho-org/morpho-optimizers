/** 
 * Supply 1 Eth to Compound using one intermidiate contract of leech
 * More details at https://compound.finance/docs
 * 
 * Remember to run your local ganache-cli with the mnemonic so you have accounts
 * with ETH in your local Ethereum environment.
 * 
 * ganache-cli \
 *     -f https://mainnet.infura.io/v3/<YOUR INFURA API KEY HERE> \
 *     -m "clutch captain shoe salt awake harvest setup primary inmate ugly among become"
 *     -i 1 \
 *     -u 0x9759A6Ac90977b93B58547b4A71c78317f391A28
 */

  // FIRST : Creation of a web3 account with the private key that is always the same thanks to the mnemonic in ganache-cli command
  const Web3 = require('web3');
  const web3 = new Web3('http://127.0.0.1:7545');

  const privateKey = '0xae756dcb08a84a119e4910d1ba4dfeb180b0ec5ec4a25223fae2669f36559dd1';
  // Add your Ethereum wallet to the Web3 object
  web3.eth.accounts.wallet.add(privateKey);
  const testWalletAddress = web3.eth.accounts.wallet[0].address; // should be 0xa0df350d2637096571F7A701CBc1C5fdE30dF76A

  // Web3 transaction information, we'll use this for every transaction we'll send
  const fromTestWallet = {
    from: testWalletAddress,
    gasLimit: web3.utils.toHex(500000),
    gasPrice: web3.utils.toHex(20000000000) // use ethgasstation.info (mainnet only)
  };


  // SECOND : Creation of the contracts


  const ethDecimals = 18; // Ethereum has 18 decimal places
  const cEthJson = require('../../abis/CEth.json');
  const cEthContractAddress = '0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5';
  const cEthContract = new web3.eth.Contract(cEthJson, cEthContractAddress)
  
  const CompoundModuleJson = require('../../abis/CompoundModule.json');
  let networkId = 1 // see the -i 1 in the ganache-cli command
  const CompoundModuleContractAddress = CompoundModuleJson.networks[networkId].address
  const CompoundModuleContract = new web3.eth.Contract(CompoundModuleJson.abi, CompoundModuleContractAddress)

  // THIRD : Setup is done now we implement the function

  const main = async function() {

    console.log(`\nNow transferring ETH from test wallet to CompoundModuleContract...\n`);

    console.log(`CompoundModuleContract now has ETH to supply to the Compound Protocol`);
    // Mint some cETH by supplying ETH to the Compound Protocol
    let amount = 1;
    amount = web3.utils.toWei(amount.toString(), 'Ether')
    fromTestWalletWithValue = fromTestWallet
    fromTestWalletWithValue.value = amount

    console.log(`CompoundModuleContract is now minting cETH...`);
    let supplyResult = await CompoundModuleContract.methods.lend().send(fromTestWalletWithValue);

    console.log(`cETH "Mint" operation successful with supply result: `, '\n');

    console.log('Here are some statistics on the intermediate contract after the mint:');
    balanceOfUnderlying = web3.utils.toBN(await cEthContract.methods
        .balanceOfUnderlying(CompoundModuleContractAddress).call()) / Math.pow(10, ethDecimals);
    console.log(`     ETH currently supplied to the Compound Protocol:`, balanceOfUnderlying);
    cEthBalance = await cEthContract.methods.balanceOf(CompoundModuleContractAddress).call() / 1e8;
    console.log(`     CompoundModuleContract's cETH Token Balance:`, cEthBalance);
    ethBalance = await web3.eth.getBalance(CompoundModuleContractAddress) / Math.pow(10, ethDecimals) / 1e8;
    console.log(`     CompoundModuleContract's ETH balance:`, ethBalance);
    cEthBalanceUser =  await cEthContract.methods.balanceOf(testWalletAddress).call() / 1e8;
    console.log(`     Test wallet's cETH balance:`, cEthBalanceUser);
    ethBalanceUser =  await web3.eth.getBalance(testWalletAddress) / Math.pow(10, ethDecimals);
    console.log(`     Test wallet's ETH balance:`, ethBalanceUser, '\n');

    // console.log(`The solidity contract recieved as variable : ${supplyResult.events.MyLog.returnValues[1]} `, '\n');
    let exchangeRateCurrent = await cEthContract.methods.exchangeRateCurrent().call();
    exchangeRateCurrent = exchangeRateCurrent / Math.pow(10, 18 + 18 - 8);
  }

  main().catch((err) => {
    console.error(err);
  });