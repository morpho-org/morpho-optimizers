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

const OracleJson = require('../../abis/ChainlinkOracle.json');
let networkId = 1 // see the -i 1 in the ganache-cli command
const OracleContract = new web3.eth.Contract(OracleJson.abi, OracleJson.networks[networkId].address)

const main = async function() {
  let supplyResult = await OracleContract.methods.consult().call(fromTestWallet)
  console.log(supplyResult)
}

main().catch((err) => {
  console.error(err);
});