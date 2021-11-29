import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';
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

  const daiAmountBob = utils.parseUnits('20000'); // 2*NMAX*SuppliedPerUser
  let Bob = '0xc03004e3ce0784bf68186394306849f9b7b12000';

  const initialize = async () => {
    // Signers
    signers = await ethers.getSigners();
    [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator] = signers;
    suppliers = [supplier1, supplier2, supplier3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy RedBlackBinaryTree
    const RedBlackBinaryTree = await ethers.getContractFactory('contracts/compound/libraries/RedBlackBinaryTree.sol:RedBlackBinaryTree');
    const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
    await redBlackBinaryTree.deployed();

    // Deploy UpdatePositions
    const UpdatePositions = await ethers.getContractFactory('contracts/compound/UpdatePositions.sol:UpdatePositions', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    const updatePositions = await UpdatePositions.deploy();
    await updatePositions.deployed();

    // Deploy MarketsManagerForCompound
    const MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
    marketsManagerForCompound = await MarketsManagerForCompound.deploy();
    await marketsManagerForCompound.deployed();

    // Deploy PositionsManagerForCompound
    const PositionsManagerForCompound = await ethers.getContractFactory('PositionsManagerForCompound', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    positionsManagerForCompound = await PositionsManagerForCompound.deploy(
      marketsManagerForCompound.address,
      config.compound.comptroller.address,
      updatePositions.address
    );
    fakeCompoundPositionsManager = await PositionsManagerForCompound.deploy(
      marketsManagerForCompound.address,
      config.compound.comptroller.address,
      updatePositions.address
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
  };

  before(initialize);

  const addSmallDaiBorrowers = async (NMAX: number) => {
    {
      const whaleUsdc = await ethers.getSigner(config.tokens.usdc.whale);
      const daiAmount = utils.parseUnits('80');
      const usdcAmount = to6Decimals(utils.parseUnits('1000'));

      for (let i = 0; i < NMAX; i++) {
        console.log('addSmallDaiBorrowers', i);

        let smallDaiBorrower = ethers.Wallet.createRandom().address;

        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallDaiBorrower],
        });

        const borrower = await ethers.getSigner(smallDaiBorrower);

        await hre.network.provider.send('hardhat_setBalance', [smallDaiBorrower, utils.hexValue(utils.parseUnits('1000'))]);
        await usdcToken.connect(whaleUsdc).transfer(smallDaiBorrower, usdcAmount);

        await usdcToken.connect(borrower).approve(positionsManagerForCompound.address, usdcAmount);
        await positionsManagerForCompound.connect(borrower).supply(config.tokens.cUsdc.address, usdcAmount);
        await positionsManagerForCompound.connect(borrower).borrow(config.tokens.cDai.address, daiAmount);
      }
    }
  };

  const addSmallDaiSuppliers = async (NMAX: number) => {
    const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
    const daiAmount = utils.parseUnits('80');

    for (let i = 0; i < NMAX; i++) {
      console.log('addSmallDaiSuppliers', i);

      let smallDaiSupplier = ethers.Wallet.createRandom().address;
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [smallDaiSupplier],
      });

      const supplier = await ethers.getSigner(smallDaiSupplier);
      await hre.network.provider.send('hardhat_setBalance', [smallDaiSupplier, utils.hexValue(utils.parseUnits('1000'))]);

      await daiToken.connect(whaleDai).transfer(smallDaiSupplier, daiAmount);
      await daiToken.connect(supplier).approve(positionsManagerForCompound.address, daiAmount);
      await positionsManagerForCompound.connect(supplier).supply(config.tokens.cDai.address, daiAmount);
    }
  };

  const addTreeDaiSuppliers = async (NMAX: number) => {
    const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
    const daiAmount = utils.parseUnits('100');

    for (let i = 0; i < NMAX; i++) {
      console.log('addTreeDaiSuppliers', i);
      let treeDaiSupplier = ethers.Wallet.createRandom().address;

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [treeDaiSupplier],
      });

      const supplier = await ethers.getSigner(treeDaiSupplier);

      await hre.network.provider.send('hardhat_setBalance', [treeDaiSupplier, utils.hexValue(utils.parseUnits('1000'))]);
      await daiToken.connect(whaleDai).transfer(treeDaiSupplier, daiAmount);

      await daiToken.connect(supplier).approve(positionsManagerForCompound.address, daiAmount);
      await positionsManagerForCompound.connect(supplier).supply(config.tokens.cDai.address, daiAmount);
    }
  };

  describe('Worst case scenario for NMAX estimation', () => {
    const NMAX = 25;

    it('Set new NMAX', async () => {
      expect(await positionsManagerForCompound.NMAX()).to.equal(1000);
      await marketsManagerForCompound.connect(owner).setMaxNumberOfUsersInTree(NMAX);
      expect(await positionsManagerForCompound.NMAX()).to.equal(NMAX);
    });

    it('Add small Dai borrowers', async () => {
      await addSmallDaiBorrowers(NMAX);
    });

    it('Add small Dai Suppliers', async () => {
      await addSmallDaiSuppliers(NMAX);
    });

    it('Add Tree Dai Suppliers', async () => {
      await addTreeDaiSuppliers(NMAX);
    });

    it('Add Bob', async () => {
      const whaleUni = await ethers.getSigner(config.tokens.uni.whale);

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [Bob],
      });

      const Bob_signer = await ethers.getSigner(Bob);

      await hre.network.provider.send('hardhat_setBalance', [Bob, utils.hexValue(utils.parseUnits('1000'))]);
      await uniToken.connect(whaleUni).transfer(Bob, daiAmountBob.mul(4));

      await uniToken.connect(Bob_signer).approve(positionsManagerForCompound.address, daiAmountBob.mul(4));
      await positionsManagerForCompound.connect(Bob_signer).supply(config.tokens.cUni.address, daiAmountBob.mul(4));
      await positionsManagerForCompound.connect(Bob_signer).borrow(config.tokens.cDai.address, daiAmountBob);
    });

    it('Bob leaves', async () => {
      const Bob_signer = await ethers.getSigner(Bob);
      console.log(await positionsManagerForCompound.borrowBalanceInOf(config.tokens.cDai.address, Bob));
      console.log(await positionsManagerForCompound.supplyBalanceInOf(config.tokens.cUni.address, Bob));

      await daiToken.connect(Bob_signer).approve(positionsManagerForCompound.address, daiAmountBob.mul(4));
      await positionsManagerForCompound.connect(Bob_signer).repay(config.tokens.cDai.address, daiAmountBob);
      await positionsManagerForCompound.connect(Bob_signer).withdraw(config.tokens.cUni.address, utils.parseUnits('19900'));
    });
  });
});
