// First run Ganache locally with `cBAT` address unlocked
/*

ganache-cli \
  -f https://mainnet.infura.io/v3/$infuraApiKey \
  -m "clutch captain shoe salt awake harvest setup primary inmate ugly among become" \
  -i 1 \
  -u 0x6c8c6b02e7b2be14d4fa6022dfd6d75921d90e4e

*/

const Web3 = require('web3');
const web3 = new Web3('http://127.0.0.1:7545');

const erc20 = require('./abis/erc20-abi.json');

const name = 'BAT';
const ud = 18; // Underlying decimals of BAT

// addresses can be found here https://github.com/compound-finance/compound-config/blob/master/networks/mainnet.json
const underlyingMainnetAddress = '0x0D8775F648430679A709E98d2b0Cb6250d2887EF';
const cTokenMainnetAddress = '0x6c8c6b02e7b2be14d4fa6022dfd6d75921d90e4e';

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
