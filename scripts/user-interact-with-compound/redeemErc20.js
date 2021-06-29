/** 
 * Redeem all Erc20 from Compound directly from javascript
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
const erc20Json = require('../../src/abis/Erc20.json');
const cErc20Json = require('../../src/abis/CErc20.json');
const ethDecimals = 18; // Ethereum has 18 decimal places

// !! change this block if you want something else than cDai
const assetName = 'DAI'; // for the log output lines
const underlyingDecimals = 18; // Number of decimals defined in this ERC20 token's contract
const daiContractAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
const cDaiContractAddress = '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643'

const underlyingMainnetAddress = daiContractAddress
const cUnderlyingMainnetAddress = cDaiContractAddress
const underlying = new web3.eth.Contract(erc20Json.abi, underlyingMainnetAddress)
const cUnderlying = new web3.eth.Contract(cErc20Json.abi, cUnderlyingMainnetAddress)


// THIRD : script
const main = async function() {

    let exchangeRateCurrent = await cUnderlying.methods.exchangeRateCurrent().call();
    exchangeRateCurrent = exchangeRateCurrent / Math.pow(10, 18 + underlyingDecimals - 8);
    console.log(`\nRedeeming the c${assetName} for ${assetName}... \nCurrent exchange rate from c${assetName} to ${assetName}:`, exchangeRateCurrent);

    // Here we chose if we want cTokens amounts as inputs for redeeming tokens (useless)
    let baseCalculationsOnCtokenAmount = true
    if (baseCalculationsOnCtokenAmount) {
        let cTokenBalance = await cUnderlying.methods.balanceOf(testWalletAddress).call() / 1e8;
        console.log(`Exchanging all c${assetName} based on cToken amount (${cTokenBalance})...`, '\n');
        if (cTokenBalance>0) {
          await cUnderlying.methods.redeem(cTokenBalance * 1e8).send(fromTestWallet);
        } else {
          console.log(`WARNING, You don't have c${assetName} so you are not redeeming anything`)
      }
    } 
    else {
        // not really implemented/tested yet
        // console.log('Exchanging all cETH based on underlying ETH amount...', '\n');
        // let ethAmount = web3.utils.toWei(balanceOfUnderlying).toString()
        // await cUnderlying.methods.redeemUnderlying(ethAmount).send(fromTestWallet);
    }
    console.log('Here are some statistics after the redeem:');
    let balanceOfUnderlying = web3.utils.toBN(await cUnderlying.methods
      .balanceOfUnderlying(testWalletAddress).call()) / Math.pow(10, ethDecimals);
    console.log(`   ${assetName} currently supplied to the Compound Protocol:`, balanceOfUnderlying);
    let ethBalance = await web3.eth.getBalance(testWalletAddress) / Math.pow(10, ethDecimals);
    console.log("   Test wallet's ETH balance:", ethBalance);
    let cTokenBalance = await cUnderlying.methods.balanceOf(testWalletAddress).call() / 1e8;
    console.log(`   Test wallet's c${assetName} Token Balance:`, cTokenBalance);
    let erc20Balance = await underlying.methods.balanceOf(testWalletAddress).call()/ Math.pow(10, underlyingDecimals);
    console.log(`   Test wallet's ${assetName} balance:`, erc20Balance, '\n');
    
}

main().catch((err) => {
    console.error(err);
});