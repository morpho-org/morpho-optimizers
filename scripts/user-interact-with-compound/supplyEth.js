/** 
 * Supply 1 Eth to Compound directly from javascript
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

const privateKey = '0x574028dad40752ed4448624f35ecb32821b0b0791652a34c10aa78053a08a730';
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
// Main Net Contract for cETH (the supply process is different for cERC20 tokens)
const ethDecimals = 18; // Ethereum has 18 decimal places
const cEthContractAddress = '0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5';
const cEthJson = require('../../src/abis/CEth.json');
const cEthContract = new web3.eth.Contract(cEthJson.abi, cEthContractAddress)


// THIRD : Scripts
const main = async function() {
  console.log('\nSupplying ETH to the Compound Protocol...', '\n');
  
  // Mint some cETH by supplying ETH to the Compound Protocol
  let amount = 1;
  amount = web3.utils.toWei(amount.toString(), 'Ether')
  fromTestWalletWithValue = fromTestWallet
  fromTestWalletWithValue.value = amount

  await cEthContract.methods.mint().send(fromTestWalletWithValue);
  
  console.log('cETH "Mint" operation successful.', '\n');

  console.log('Here are some statistics after the mint :');
  let balanceOfUnderlying = web3.utils.toBN(await cEthContract.methods
    .balanceOfUnderlying(testWalletAddress).call()) / Math.pow(10, ethDecimals);
  console.log("   ETH currently supplied to the Compound Protocol:", balanceOfUnderlying);
  let cTokenBalance = await cEthContract.methods.balanceOf(testWalletAddress).call() / 1e8;
  console.log("   Test wallet's cETH Token Balance:", cTokenBalance);
  let ethBalance = await web3.eth.getBalance(testWalletAddress) / Math.pow(10, ethDecimals);
  console.log("   Test wallet's ETH balance:", ethBalance, '\n');

}


main().catch((err) => {
  console.error("\n\n",err);
});