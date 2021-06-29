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


  const ethDecimals = 18; // Ethereum has 18 decimal places
  const cEthJson = require('../../abis/CEth.json');
  const cEthContractAddress = '0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5';
  const cEthContract = new web3.eth.Contract(cEthJson.abi, cEthContractAddress)
  
  const CompoundModuleJson = require('../../abis/CompoundModule.json');
  let networkId = 1 // see the -i 1 in the ganache-cli command
  const CompoundModuleContractAddress = CompoundModuleJson.networks[networkId].address
  const CompoundModuleContract = new web3.eth.Contract(CompoundModuleJson.abi, CompoundModuleContractAddress)


  // THIRD : Setup is done now we implement the function

  const main = async function() {

    // Call redeem based on a cEth amount
    console.log(`Redeeming the cETH for ETH...`);
    let cEthBalance = await cEthContract.methods.balanceOf(CompoundModuleContractAddress).call() / 1e8;
    console.log(`CompoundModuleContract's cETH Token Balance:`, cEthBalance);
    const amount = web3.utils.toHex(cEthBalance * 1e8);

    let redeemResult = await CompoundModuleContract.methods.cashOut(
      amount).send(fromTestWallet);


    // // OR   Call redeem based on a Eth amount
    // let balanceOfUnderlying = web3.utils.toBN(await cEthContract.methods
    //   .balanceOfUnderlying(CompoundModuleContractAddress).call()) / Math.pow(10, ethDecimals);
    // console.log(`     ETH currently supplied to the Compound Protocol:`, balanceOfUnderlying);     
    // let ethBalance = web3.utils.toWei(balanceOfUnderlying.toString())
    // // const amount = web3.utils.toHex(ethBalance * 1e8);
    // console.log(`Redeeming the cETH for ETH...`);
    // let redeemResult = await CompoundModuleContract.methods.redeemCEth(
    //   ethBalance,
    //   redeemType=false,
    //   cEthContractAddress
    // ).send(fromTestWallet);



    if (redeemResult.events.MyLog.returnValues[1] != 0) {
      throw Error('Redeem Error Code: '+redeemResult.events.MyLog.returnValues[1]);
    }

    console.log('Here are some statistics on the intermediate contract after the mint:');
     balanceOfUnderlying = web3.utils.toBN(await cEthContract.methods
        .balanceOfUnderlying(CompoundModuleContractAddress).call()) / Math.pow(10, ethDecimals);
    console.log(`     ETH currently supplied to the Compound Protocol:`, balanceOfUnderlying);
    cEthBalance = await cEthContract.methods.balanceOf(CompoundModuleContractAddress).call()/ 1e8;
    console.log(`     CompoundModuleContract's cETH Token Balance:`, cEthBalance);
    let ethBalance = await await web3.eth.getBalance(CompoundModuleContractAddress) / Math.pow(10, ethDecimals);
    console.log(`     CompoundModuleContract's ETH balance:`, ethBalance);
    let cEthBalanceUser =  await cEthContract.methods.balanceOf(testWalletAddress).call() / 1e8;
    console.log(`     Test wallet's cETH balance:`, cEthBalanceUser);
    let ethBalanceUser =  await web3.eth.getBalance(testWalletAddress) / Math.pow(10, ethDecimals);
    console.log(`     Test wallet's ETH balance:`, ethBalanceUser, '\n');
  }

  main().catch((err) => {
    console.error(err);
  });