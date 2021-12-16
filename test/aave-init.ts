import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { BigNumber, Contract, Signer } from 'ethers';
import hre, { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { MAX_INT, to6Decimals } from './utils/common-helpers';

import { WAD } from './utils/aave-helpers';

// RUN: ganache-cli --fork https://polygon-mainnet.infura.io/v3/3f24d90096a34121a0b037dee8a8d4f2 -l 30000000 --mnemonic "snake snake snake snake snake snake snake snake snake snake snake snake" --db ./ganache-db/
// Owner is: 0xFd2DDc3693a62CB447F778f3c4a94fC722DC19b5
// His private key: 0x89da9b678e04546984f37c39e04b11153f92fa027454e8266f5ab1149d895733

// Tokens
let aDaiToken: Contract;
let aUsdcToken: Contract;
let daiToken: Contract;
let usdcToken: Contract;
let variableDebtDaiToken: Contract;

// Contracts
let positionsManagerForAave: Contract;
let marketsManagerForAave: Contract;
let fakeAavePositionsManager: Contract;
let lendingPool: Contract;
let lendingPoolAddressesProvider: Contract;
let protocolDataProvider: Contract;
let oracle: Contract;

let owner: Signer;

describe('Create a local fork', () => {
  it('Start init', async () => {
    ethers.provider = new ethers.providers.JsonRpcProvider('http://127.0.0.1:8545/');
    owner = await ethers.getSigner('0xFd2DDc3693a62CB447F778f3c4a94fC722DC19b5');

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

    // Get contract dependencies
    const aTokenAbi = require(config.tokens.aToken.abi);
    const variableDebtTokenAbi = require(config.tokens.variableDebtToken.abi);
    aDaiToken = await ethers.getContractAt(aTokenAbi, config.tokens.aDai.address, owner);
    aUsdcToken = await ethers.getContractAt(aTokenAbi, config.tokens.aUsdc.address, owner);
    variableDebtDaiToken = await ethers.getContractAt(variableDebtTokenAbi, config.tokens.variableDebtDai.address, owner);
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

    // Create and list markets
    await marketsManagerForAave.connect(owner).setPositionsManager(positionsManagerForAave.address);
    await marketsManagerForAave.connect(owner).setLendingPool();
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, WAD, MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(WAD), MAX_INT);
  });
});
