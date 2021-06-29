// First run Ganache locally with `cUSDC` address unlocked
/*

ganache-cli \
  -f https://mainnet.infura.io/v3/$infuraApiKey \
  -m "clutch captain shoe salt awake harvest setup primary inmate ugly among become" \
  -i 1 \
  -u 0x39AA39c021dfbaE8faC545936693aC917d5E7563

*/

const Web3 = require('web3');
const web3 = new Web3('http://127.0.0.7545');

const erc20 = require('./abis/erc20-abi.json');

const name = 'USDC';
const ud = 6; // Underlying decimals of USDC

// addresses can be found here https://github.com/compound-finance/compound-config/blob/master/networks/mainnet.json
const underlyingMainnetAddress = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const cTokenMainnetAddress = '0x39AA39c021dfbaE8faC545936693aC917d5E7563';

const underlyingContract = new web3.eth.Contract(erc20, underlyingMainnetAddress);
const cTokenContract = new web3.eth.Contract(erc20, cTokenMainnetAddress);

let accounts;

web3.eth.getAccounts().then((ganacheAccounts) => {
  accounts = ganacheAccounts;

  // 50 tokens
  const numbTokensToMint = (50 * Math.pow(10, ud)).toString();

  return underlyingContract.methods.transfer(accounts[0], numbTokensToMint).send({ 
    from: cTokenMainnetAddress,
    gasPrice: web3.utils.toHex(0),
    gas: 3000000
  });

}).then((result) => {
  console.log('Local test account successfully seeded with ' + name);
  return underlyingContract.methods.balanceOf(accounts[0]).call();
}).then((balanceOf) => {
  const tokens = +balanceOf / Math.pow(10, ud);
  console.log(name + ' amount in first Ganache account wallet:', tokens);
}).catch((err) => {
  console.error(err);
});
