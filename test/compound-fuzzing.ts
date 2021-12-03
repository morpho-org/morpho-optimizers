import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers, network } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { removeDigitsBigNumber, bigNumberMin, to6Decimals, getTokens } from './utils/common-helpers';
import {
  WAD,
  underlyingToCToken,
  cTokenToUnderlying,
  underlyingToP2pUnit,
  p2pUnitToUnderlying,
  underlyingToCdUnit,
  cDUnitToUnderlying,
  computeNewMorphoExchangeRate,
} from './utils/compound-helpers';

type Market = {
  token: Contract;
  config: any;
  cToken: Contract;
  collateralFactor: number; // in percent
  name: string;
};

describe('PositionsManagerForCompound Contract', () => {
  // Tokens
  let cUsdcToken: Contract;
  let cDaiToken: Contract;
  let cMkrToken: Contract;
  let daiToken: Contract;
  let uniToken: Contract;
  let usdcToken: Contract;

  // Contracts
  let positionsManagerForCompound: Contract;
  let marketsManagerForCompound: Contract;
  let fakeCompoundPositionsManager: Contract;
  let comptroller: Contract;
  let compoundOracle: Contract;
  let priceOracle: Contract;

  // Signers
  let signers: Signer[];
  let suppliers: Signer[];
  let borrowers: Signer[];
  let owner: Signer;
  let supplier1: Signer;
  let supplier2: Signer;
  let supplier3: Signer;
  let borrower1: Signer;
  let borrower2: Signer;
  let borrower3: Signer;
  let liquidator: Signer;

  let underlyingThreshold: BigNumber;
  let snapshotId: number;

  let markets: Array<Market> = [];

  const initialize = async () => {
    // Signers
    signers = await ethers.getSigners();
    [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator] = signers;
    suppliers = [supplier1, supplier2, supplier3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy DoubleLinkedList
    const DoubleLinkedList = await ethers.getContractFactory('contracts/compound/libraries/DoubleLinkedList.sol:DoubleLinkedList');
    const doubleLinkedList = await DoubleLinkedList.deploy();
    await doubleLinkedList.deployed();

    // Deploy MarketsManagerForCompound
    const MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
    marketsManagerForCompound = await MarketsManagerForCompound.deploy();
    await marketsManagerForCompound.deployed();

    // Deploy PositionsManagerForCompound
    const PositionsManagerForCompound = await ethers.getContractFactory('PositionsManagerForCompound');
    positionsManagerForCompound = await PositionsManagerForCompound.deploy(
      marketsManagerForCompound.address,
      config.compound.comptroller.address
    );
    fakeCompoundPositionsManager = await PositionsManagerForCompound.deploy(
      marketsManagerForCompound.address,
      config.compound.comptroller.address
    );
    await positionsManagerForCompound.deployed();
    await fakeCompoundPositionsManager.deployed();

    // Get contract dependencies
    const cTokenAbi = require(config.tokens.cToken.abi);
    cUsdcToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdc.address, owner);
    cDaiToken = await ethers.getContractAt(cTokenAbi, config.tokens.cDai.address, owner);
    cMkrToken = await ethers.getContractAt(cTokenAbi, config.tokens.cMkr.address, owner); // This is in fact crLINK tokens (no crMKR on Polygon)

    comptroller = await ethers.getContractAt(require(config.compound.comptroller.abi), config.compound.comptroller.address, owner);
    compoundOracle = await ethers.getContractAt(require(config.compound.oracle.abi), comptroller.oracle(), owner);

    // Mint some tokens
    daiToken = await getTokens(config.tokens.dai.whale, 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
    usdcToken = await getTokens(config.tokens.usdc.whale, 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    uniToken = await getTokens(config.tokens.uni.whale, 'whale', signers, config.tokens.uni, utils.parseUnits('100'));

    underlyingThreshold = WAD;

    // Create and list markets
    await marketsManagerForCompound.connect(owner).setPositionsManager(positionsManagerForCompound.address);
    await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cDai.address, WAD);
    await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cUsdc.address, to6Decimals(WAD));
    await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cUni.address, WAD);
    await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cUsdt.address, to6Decimals(WAD));

    let daiMarket: Market = {
      token: daiToken,
      config: config.tokens.dai,
      cToken: cDaiToken,
      collateralFactor: 80,
      name: 'dai',
    };
    let usdcMarket: Market = {
      token: usdcToken,
      config: config.tokens.usdc,
      cToken: cUsdcToken,
      collateralFactor: 80,
      name: 'usdc',
    };
    // let uniMarket: Market = {
    //   token: uniToken,
    //   config: config.tokens.uni,
    //   cToken: cUni
    // };
    markets = [daiMarket, usdcMarket];
  };

  const toBytes32 = (bn: BigNumber) => {
    return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
  };

  const setStorageAt = async (address: string, index: string, value: string) => {
    await ethers.provider.send('hardhat_setStorageAt', [address, index, value]);
    await ethers.provider.send('evm_mine', []); // Just mines to the next block
  };

  const tokenAmountToReadable = (bn: BigNumber, token: Contract) => {
    if (isA6DecimalsToken(token)) return bn.div(1e6).toString();
    else return bn.div(WAD).toString();
  };

  const giveTokensTo = async (token: string, receiver: string, amount: BigNumber) => {
    // Get storage slot index
    let index = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [receiver, 0] // key, slot
    );
    await setStorageAt(token, index, toBytes32(amount));
  };

  const isA6DecimalsToken = (token: Contract) => {
    return token.address === config.tokens.usdc.address || token.address === config.tokens.usdt.address;
  };

  before(initialize);

  describe('FUZZZZZZ EVERYTHING 🐙', () => {
    let amount: BigNumber;
    let supplierAddress: string;
    let tokenDropFailed: boolean = false;
    let suppliedAmount: BigNumber;
    let withrewAmount: BigNumber;
    let borrowedMarket: Market;
    let borrowedAmount: BigNumber;

    it('fouzzzz 🦑', async () => {
      for await (let market of markets) {
        for await (let i of [...Array(100).keys()]) {
          console.log(i);
          let supplier: Signer = ethers.Wallet.createRandom();
          supplier = supplier.connect(ethers.provider);
          supplierAddress = await supplier.getAddress();
          await hre.network.provider.send('hardhat_setBalance', [supplierAddress, utils.hexValue(utils.parseUnits('10000'))]);

          // the amount to repay is chosen randomly between 1 and 1000 (1 minimum to avoid errors because below threshold)
          amount = utils.parseUnits(Math.round(Math.random() * 1000).toString()).add(WAD);
          if (market.token.address === config.tokens.usdc.address || market.token.address === config.tokens.usdt.address) {
            amount = to6Decimals(amount);
          }
          try {
            await giveTokensTo(market.token.address, supplierAddress, amount);
          } catch {
            tokenDropFailed = true;
            console.log('token drop fail (skipping this one)');
          }
          if (!tokenDropFailed) {
            await market.token.connect(supplier).approve(positionsManagerForCompound.address, amount);
            await positionsManagerForCompound.connect(supplier).supply(market.cToken.address, amount);
            suppliedAmount = amount;
            console.log('supplied ', tokenAmountToReadable(amount, market.token), ' ', market.name);

            // we withdraw a random withdrawable amount with a probability of 1/2
            if (Math.random() > 0.5) {
              withrewAmount = amount.mul(BigNumber.from(Math.round(1000 * Math.random()))).div(1000);
              await positionsManagerForCompound.connect(supplier).withdraw(market.cToken.address, withrewAmount);
              console.log('withdrew ', tokenAmountToReadable(withrewAmount, market.token), ' ', market.name);
              suppliedAmount = suppliedAmount.sub(withrewAmount);
              console.log('remains ', tokenAmountToReadable(suppliedAmount, market.token), ' ', market.name);
            }
            // 80% chance
            if (Math.random() > 0.2) {
              borrowedMarket = markets[Math.floor(Math.random() * markets.length)]; // select a random market to borrow
              borrowedAmount = suppliedAmount
                .mul(market.collateralFactor)
                .div(100)
                .mul(Math.floor(1000 * Math.random()))
                .div(1000); // borrow random amount possible with what was supplied
              if (!isA6DecimalsToken(market.token) && isA6DecimalsToken(borrowedMarket.token)) {
                borrowedAmount = borrowedAmount.div(BigNumber.from(10).pow(12)); // reduce to a 6 decimals equivalent amount
              }
              // don't borrow if below threshold
              if (borrowedAmount > WAD) {
                console.log('borrowed ', tokenAmountToReadable(borrowedAmount, borrowedMarket.token), ' ', borrowedMarket.name);
                await positionsManagerForCompound.connect(supplier).borrow(borrowedMarket.cToken.address, borrowedAmount);
              }
            }
          }
          tokenDropFailed = false;
        }
      }
    });
  });
});
