// First run Ganache locally with `cZRX` address unlocked
/*

ganache-cli \
  -f https://mainnet.infura.io/v3/$infuraApiKey \
  -m "clutch captain shoe salt awake harvest setup primary inmate ugly among become" \
  -i 1 \
  -u 0xb3319f5d18bc0d84dd1b4825dcde5d5f7266d407

*/

const Web3 = require('web3');
const web3 = new Web3('http://127.0.0.1:7545');

const erc20 = require('./abis/erc20-abi.json');

const name = 'ZRX';
const ud = 18; // Underlying decimals of ZRX

// addresses can be found here https://github.com/compound-finance/compound-config/blob/master/networks/mainnet.json
const underlyingMainnetAddress = '0xE41d2489571d322189246DaFA5ebDe1F4699F498';
const cTokenMainnetAddress = '0xb3319f5d18bc0d84dd1b4825dcde5d5f7266d407';

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
