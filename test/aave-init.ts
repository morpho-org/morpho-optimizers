import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { MAX_INT, to6Decimals, getTokens } from './utils/common-helpers';

import { WAD } from './utils/aave-helpers';

// RUN :
// ganache-cli --fork https://polygon-mainnet.infura.io/v3/3f24d90096a34121a0b037dee8a8d4f2 -l 30000000 --mnemonic "snake snake snake snake snake snake snake snake snake snake snake snake" --db ./local-chain/ --unlock "0x56CF0ff00fd6CfB23ce964C6338B228B0FA76640"
// THEN (in another terminal) :
// npx hardhat test test/aave-init.ts

// Tokens
let daiToken: Contract;
let usdcToken: Contract;

// Contracts
let positionsManagerForAave: Contract;
let marketsManagerForAave: Contract;
let fakeAavePositionsManager: Contract;
let lendingPool: Contract;
let lendingPoolAddressesProvider: Contract;
let protocolDataProvider: Contract;
let oracle: Contract;

let owner: Signer;
const ownerAddress: string = '0xFd2DDc3693a62CB447F778f3c4a94fC722DC19b5';
const whaleAddress: string = '0x56CF0ff00fd6CfB23ce964C6338B228B0FA76640';

describe('Create a local fork', () => {
  it('Start init', async () => {
    ethers.provider = new ethers.providers.JsonRpcProvider('http://127.0.0.1:8545/');
    owner = await ethers.getSigner(ownerAddress);
    const whale: Signer = await ethers.getSigner(whaleAddress);

    // Deploy MarketsManagerForAave
    const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
    marketsManagerForAave = await MarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
    await marketsManagerForAave.deployed();

    // Deploy PositionsManagerForAave
    const PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave');
    positionsManagerForAave = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address
    );
    fakeAavePositionsManager = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address
    );
    await positionsManagerForAave.deployed();
    await fakeAavePositionsManager.deployed();

    console.log('positions', positionsManagerForAave.address);

    // Get contract dependencies
    const aTokenAbi = require(config.tokens.aToken.abi);
    const variableDebtTokenAbi = require(config.tokens.variableDebtToken.abi);
    lendingPool = await ethers.getContractAt(require(config.aave.lendingPool.abi), config.aave.lendingPool.address, owner);
    lendingPoolAddressesProvider = await ethers.getContractAt(
      require(config.aave.lendingPoolAddressesProvider.abi),
      config.aave.lendingPoolAddressesProvider.address,
      owner
    );
    protocolDataProvider = await ethers.getContractAt(
      require(config.aave.protocolDataProvider.abi),
      lendingPoolAddressesProvider.getAddress('0x1000000000000000000000000000000000000000000000000000000000000000'),
      owner
    );
    oracle = await ethers.getContractAt(require(config.aave.oracle.abi), lendingPoolAddressesProvider.getPriceOracle(), owner);

    // Mint some tokens
    daiToken = await ethers.getContractAt(require(config.tokens.dai.abi), config.tokens.dai.address, owner);
    usdcToken = await ethers.getContractAt(require(config.tokens.usdc.abi), config.tokens.usdc.address, owner);

    // Give tokens to owner for later
    await daiToken.connect(whale).transfer(ownerAddress, ethers.utils.parseUnits('2000'));
    await usdcToken.connect(whale).transfer(ownerAddress, to6Decimals(ethers.utils.parseUnits('2000')));

    // Create and list markets
    await marketsManagerForAave.connect(owner).setPositionsManager(positionsManagerForAave.address);
    await marketsManagerForAave.connect(owner).setLendingPool();
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, WAD, MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address, BigNumber.from(10).pow(4), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address, WAD, MAX_INT);
  });

  it('Owner uses Morpho so that AAVE is saved on disk', async () => {
    // await giveTokensTo(daiToken.address, await owner.getAddress(), utils.parseUnits('10000'), 0);

    const daiAmount = utils.parseUnits('1000');
    const usdcAmmount = to6Decimals(utils.parseUnits('500'));

    console.log('1');
    // supply DAI
    await daiToken.connect(owner).approve(positionsManagerForAave.address, daiAmount);
    await positionsManagerForAave.connect(owner).supply(config.tokens.aDai.address, daiAmount);

    console.log('2');
    // Borrow USDC
    await positionsManagerForAave.connect(owner).borrow(config.tokens.aUsdc.address, usdcAmmount);

    console.log('3');
    // Repay USDC
    await usdcToken.connect(owner).approve(positionsManagerForAave.address, usdcAmmount);
    await positionsManagerForAave.connect(owner).repay(config.tokens.aUsdc.address, usdcAmmount);

    console.log('4');
    // Withdraw DAI
    await positionsManagerForAave.connect(owner).withdraw(config.tokens.aDai.address, daiAmount);
  });
});
