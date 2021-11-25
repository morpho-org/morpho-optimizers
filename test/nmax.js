require('dotenv').config({ path: '.env.local' });
const { utils, BigNumber } = require('ethers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const hre = require('hardhat');
const config = require(`@config/${process.env.NETWORK}-config.json`);
const {
  SCALE,
  underlyingToCToken,
  cTokenToUnderlying,
  underlyingToP2pUnit,
  p2pUnitToUnderlying,
  underlyingToCdUnit,
  cDUnitToUnderlying,
  removeDigitsBigNumber,
  bigNumberMin,
  to6Decimals,
  computeNewMorphoExchangeRate,
  getTokens,
} = require('./utils/helpers');

describe('PositionsManagerForCompound Contract', () => {
  let cUsdcToken;
  let cDaiToken;
  let cUsdtToken;
  let cMkrToken;
  let daiToken;
  let uniToken;
  let PositionsManagerForCompound;
  let positionsManagerForCompound;
  let MarketsManagerForCompound;
  let marketsManagerForCompound;
  let fakeCompoundPositionsManager;

  let signers;
  let owner;
  let supplier1;
  let supplier2;
  let supplier3;
  let borrower1;
  let borrower2;
  let borrower3;
  let liquidator;
  let addrs;
  let suppliers;
  let borrowers;

  let underlyingThreshold;
  let snapshotId;

  const NMAX = 100;
  const daiAmount = utils.parseUnits('20000'); // 2*NMAX*SuppliedPerUser
  let Bob = '0xc03004e3ce0784bf68186394306849f9b7b12000';

  const initialize = async () => {
    {
      // Users
      signers = await ethers.getSigners();
      [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
      suppliers = [supplier1, supplier2, supplier3];
      borrowers = [borrower1, borrower2, borrower3];

      const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
      const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
      await redBlackBinaryTree.deployed();

      const UpdatePositions = await ethers.getContractFactory('UpdatePositions', {
        libraries: {
          RedBlackBinaryTree: redBlackBinaryTree.address,
        },
      });
      const updatePositions = await UpdatePositions.deploy();
      await updatePositions.deployed();

      // Deploy contracts
      MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
      marketsManagerForCompound = await MarketsManagerForCompound.deploy();
      await marketsManagerForCompound.deployed();

      PositionsManagerForCompound = await ethers.getContractFactory('PositionsManagerForCompound', {
        libraries: {
          RedBlackBinaryTree: redBlackBinaryTree.address,
        },
      });
      positionsManagerForCompound = await PositionsManagerForCompound.deploy(marketsManagerForCompound.address, config.compound.comptroller.address, updatePositions.address);
      fakeCompoundPositionsManager = await PositionsManagerForCompound.deploy(marketsManagerForCompound.address, config.compound.comptroller.address, updatePositions.address);
      await positionsManagerForCompound.deployed();
      await fakeCompoundPositionsManager.deployed();

      // Get contract dependencies
      const cTokenAbi = require(config.tokens.cToken.abi);
      cUsdcToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdc.address, owner);
      cDaiToken = await ethers.getContractAt(cTokenAbi, config.tokens.cDai.address, owner);
      cUsdtToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdt.address, owner);
      cUniToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUni.address, owner);
      cMkrToken = await ethers.getContractAt(cTokenAbi, config.tokens.cMkr.address, owner); // This is in fact crLINK tokens (no crMKR on Polygon)

      comptroller = await ethers.getContractAt(require(config.compound.comptroller.abi), config.compound.comptroller.address, owner);
      compoundOracle = await ethers.getContractAt(require(config.compound.oracle.abi), comptroller.oracle(), owner);

      // Mint some ERC20
      daiToken = await getTokens(config.tokens.dai.whale, 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
      usdcToken = await getTokens(config.tokens.usdc.whale, 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
      usdtToken = await getTokens(config.tokens.usdt.whale, 'whale', signers, config.tokens.usdt, BigNumber.from(10).pow(10));
      uniToken = await getTokens(config.tokens.uni.whale, 'whale', signers, config.tokens.uni, utils.parseUnits('100'));

      underlyingThreshold = utils.parseUnits('1');

      // Create and list markets
      await marketsManagerForCompound.connect(owner).setPositionsManagerForCompound(positionsManagerForCompound.address);
      await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cDai.address, utils.parseUnits('1'));
      await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cUsdc.address, to6Decimals(utils.parseUnits('1')));
      await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cUni.address, utils.parseUnits('1'));
      await marketsManagerForCompound.connect(owner).createMarket(config.tokens.cUsdt.address, to6Decimals(utils.parseUnits('1')));
    }
  };

  before(initialize);

  const addSmallDaiBorrowers = async (NMAX) => {
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
        await positionsManagerForCompound.connect(borrower).supply(config.tokens.cusdc.address, usdcAmount);
        await positionsManagerForCompound.connect(borrower).borrow(config.tokens.cdai.address, daiAmount);
      }
    }
  };

  const addSmallDaiSuppliers = async (NMAX) => {
    const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
    console.log(whaleDai);
    const daiAmount = utils.parseUnits('80');

    for (let i = 0; i < NMAX; i++) {
      console.log(NMAX);
      let smallDaiSupplier = ethers.Wallet.createRandom().address;
      console.log('a');
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [smallDaiSupplier],
      });
      console.log('b');
      const supplier = await ethers.getSigner(smallDaiSupplier);
      console.log('c');
      await hre.network.provider.send('hardhat_setBalance', [smallDaiSupplier, utils.hexValue(utils.parseUnits('1000'))]);
      await daiToken.connect(whaleDai).transfer(smallDaiSupplier, daiAmount);
      console.log('d');
      await daiToken.connect(supplier).approve(positionsManagerForCompound.address, daiAmount);
      await positionsManagerForCompound.connect(supplier).supply(config.tokens.cdai.address, daiAmount);
      console.log('addSmallDaiSuppliers', i);
    }
  };

  const addTreeDaiSuppliers = async (NMAX) => {
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
      await daiToken.connect(whaleDai).transfer(smallDaiSupplier, daiAmount);

      await daiToken.connect(supplier).approve(positionsManagerForCompound.address, daiAmount);
      await positionsManagerForCompound.connect(supplier).supply(config.tokens.cDai.address, daiAmount);
    }
  };

  describe('Worst case scenario for NMAX estimation', () => {
    it('Add small Dai borrowers', async () => {
      addSmallDaiBorrowers(NMAX);
    });

    it.only('Add small Dai Suppliers', async () => {
      addSmallDaiSuppliers(NMAX);
    });

    it('Add Tree Dai Suppliers', async () => {
      addTreeDaiSuppliers(NMAX);
    });

    it('Add Bob', async () => {
      const whaleUni = await ethers.getSigner(config.tokens.uni.whale);

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [Bob],
      });

      const Bob_signer = await ethers.getSigner(Bob);

      await hre.network.provider.send('hardhat_setBalance', [Bob, utils.hexValue(utils.parseUnits('1000'))]);
      await uniToken.connect(whaleUni).transfer(Bob, daiAmount.mul(4));

      await uniToken.connect(Bob_signer).approve(positionsManagerForCompound.address, daiAmount.mul(4));
      await positionsManagerForCompound.connect(Bob_signer).supply(config.tokens.cUni.address, daiAmount.mul(4));
      await positionsManagerForCompound.connect(Bob_signer).borrow(config.tokens.cDai.address, daiAmount);
    });

    it('Bob leaves', async () => {
      const Bob_signer = await ethers.getSigner(Bob);
      console.log(await positionsManagerForCompound.borrowBalanceInOf(config.tokens.cDai.address, Bob));
      console.log(await positionsManagerForCompound.supplyBalanceInOf(config.tokens.cUni.address, Bob));

      await daiToken.connect(Bob_signer).approve(positionsManagerForCompound.address, daiAmount.mul(4));
      await positionsManagerForCompound.connect(Bob_signer).repay(config.tokens.cDai.address, daiAmount);
      await positionsManagerForCompound.connect(Bob_signer).withdraw(config.tokens.cUni.address, utils.parseUnits('19900'));
    });
  });
});
