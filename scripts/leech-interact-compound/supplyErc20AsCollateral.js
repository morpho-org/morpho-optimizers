/** 
 * Supply 1 Erc20 to Compound using one intermidiate contract of leech
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
  const erc20Json = require('../../abis/Erc20.json');
  const cErc20Json = require('../../abis/CErc20.json');
  const CompoundModuleJson = require('../../abis/CompoundModule.json');


  // Instanciation of the contracts of the Underlying token contract address. Example: Dai.
  // !! change this block if you want something else than Dai
  const assetName = 'DAI'; // for the log output lines
  const underlyingDecimals = 18; // Number of decimals defined in this ERC20 token's contract
  const daiContractAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
  const cDaiContractAddress = '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643'
  const underlyingMainnetAddress = daiContractAddress
  const cUnderlyingMainnetAddress = cDaiContractAddress

  const underlying = new web3.eth.Contract(erc20Json.abi, underlyingMainnetAddress)
  const cUnderlying = new web3.eth.Contract(cErc20Json.abi, cUnderlyingMainnetAddress)
  // We fetch the address of the deployed contract
  let networkId = 1 // see the -i 1 in the ganache-cli command
  const CompoundModuleContractAddress = CompoundModuleJson.networks[networkId].address
  const CompoundModuleContract = new web3.eth.Contract(CompoundModuleJson.abi, CompoundModuleContractAddress)



  // THIRD : Setup is done now we implement the function

  const main = async function() {
    console.log(`\nNow transferring ${assetName} from test wallet to CompoundModuleContract...`);

    let transferResult = await underlying.methods.transfer(
      CompoundModuleContractAddress,
      web3.utils.toHex(1 * Math.pow(10, underlyingDecimals)) // 10 tokens to send to CompoundModuleContract
    ).send(fromTestWallet);

    console.log(`CompoundModuleContract now has ${assetName} to supply to the Compound Protocol`);

    // Mint some cUnderlying by sending Underlying to the Compound Protocol
    console.log(`CompoundModuleContract is now minting c${assetName}...`);
    let supplyResult = await CompoundModuleContract.methods.provideCollateral(
      web3.utils.toHex(1 * Math.pow(10, underlyingDecimals)) // 10 tokens to supply
    ).send(fromTestWallet);
    console.log(`c${assetName} "Mint" operation successful`, '\n');


    console.log('Here are some statistics on the intermediate contract after the mint:');
    let balanceOfUnderlying = await cUnderlying.methods
      .balanceOfUnderlying(CompoundModuleContractAddress).call() / Math.pow(10, underlyingDecimals);
    console.log(`     ${assetName} supplied to the Compound Protocol:`, balanceOfUnderlying);
    let cUnderlyingBalance = await cUnderlying.methods.balanceOf(CompoundModuleContractAddress).call();
    cUnderlyingBalance = cUnderlyingBalance / 1e8;
    console.log(`     CompoundModuleContract's c${assetName} Token Balance:`, cUnderlyingBalance);
    let erc20Balance = await underlying.methods.balanceOf(CompoundModuleContractAddress).call()/ Math.pow(10, underlyingDecimals);
    console.log(`     CompoundModuleContract's ${assetName} balance:`, erc20Balance);
    let erc20BalanceUser = await underlying.methods.balanceOf(testWalletAddress).call()/ Math.pow(10, underlyingDecimals);
    console.log(`     Test wallet's ${assetName} balance:`, erc20BalanceUser, '\n');
  }

  main().catch((err) => {
    console.error(err);
  });