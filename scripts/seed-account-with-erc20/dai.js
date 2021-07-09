// First run Ganache locally with `daiMcdJoin` address unlocked
/*

ganache-cli \
  -f https://mainnet.infura.io/v3/$infuraApiKey \
  -m "clutch captain shoe salt awake harvest setup primary inmate ugly among become" \
  -i 1 \
  -u 0x9759A6Ac90977b93B58547b4A71c78317f391A28

*/

const Web3 = require('web3');
const web3 = new Web3('http://127.0.0.1:7545');

const daiAbi = require('./abis/dai-abi.json');

// Address of DAI contract https://etherscan.io/address/0x6b175474e89094c44da98b954eedeac495271d0f
const daiMainNetAddress = '0x6b175474e89094c44da98b954eedeac495271d0f';

// Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
const daiMcdJoin = '0x9759A6Ac90977b93B58547b4A71c78317f391A28';

let daiContract;
let accounts;

web3.eth.getAccounts().then((ganacheAccounts) => {

  accounts = ganacheAccounts;

  daiContract = new web3.eth.Contract(daiAbi, daiMainNetAddress);

  // 50 DAI
  const numbDaiToMint = web3.utils.toWei('5000', 'ether');
  console.log('Setup successful');

  return daiContract.methods.mint(accounts[0], numbDaiToMint)
    .send({ 
      from: daiMcdJoin,
      gasPrice: web3.utils.toHex(0)
    });
}).then((result) => {
  console.log('DAI mint success');
  return daiContract.methods.balanceOf(accounts[0]).call();
}).then((balanceOf) => {
  const dai = balanceOf / 1e18;
  console.log('DAI amount in first Ganache account wallet:', dai);
}).catch((err) => {
  console.error(err);
});
