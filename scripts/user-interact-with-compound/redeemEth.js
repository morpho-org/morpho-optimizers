/** 
 * Redeem all Eth from Compound directly from javascript
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

    let exchangeRateCurrent = await cEthContract.methods.exchangeRateCurrent().call();
    exchangeRateCurrent = exchangeRateCurrent / Math.pow(10, 18 + ethDecimals - 8);
    console.log('\nRedeeming the cETH for ETH... \nCurrent exchange rate from cETH to ETH:', exchangeRateCurrent, '\n');
    
    // Here we chose if we want cTokens amounts as inputs for redeeming tokens (useless)
    let baseCalculationsOnCtokenAmount = true
    if (baseCalculationsOnCtokenAmount) {
        // The first method, redeem, redeems ETH based on the cToken amount passed to the function call.
        let cTokenBalance = await cEthContract.methods.balanceOf(testWalletAddress).call() / 1e8;
        console.log('   Exchanging all cETH based on cToken amount...');
        if (cTokenBalance>0) {
            await cEthContract.methods.redeem(cTokenBalance * 1e8).send(fromTestWallet);
        } else {
            console.log("WARNING, You don't have cETH so you are not redeeming anything")
        }
        
    } else {
        // The second method, redeemUnderlying, redeems ETH based on the ETH amount passed to the function call.
        console.log('   Exchanging all cETH based on underlying ETH amount...');
        const balanceOfUnderlying = web3.utils.toBN(await cEthContract.methods
            .balanceOfUnderlying(testWalletAddress).call()) / Math.pow(10, ethDecimals);        
        let ethAmount = web3.utils.toWei(balanceOfUnderlying.toString())
        await cEthContract.methods.redeemUnderlying(ethAmount).send(fromTestWallet);
    }

    console.log('Here are some statistics after the redeem:');
    let balanceOfUnderlying = web3.utils.toBN(await cEthContract.methods
        .balanceOfUnderlying(testWalletAddress).call()) / Math.pow(10, ethDecimals);
    console.log("       ETH currently supplied to the Compound Protocol:", balanceOfUnderlying);
    cTokenBalance = await cEthContract.methods.balanceOf(testWalletAddress).call() / 1e8;
    console.log("       Test wallet's cETH Token Balance:", cTokenBalance);
    ethBalance = await web3.eth.getBalance(testWalletAddress) / Math.pow(10, ethDecimals);
    console.log("       Test wallet's ETH balance:", ethBalance, '\n');
}

main().catch((err) => {
    console.error("\n\n",err);
});