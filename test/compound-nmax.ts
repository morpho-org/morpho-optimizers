/* eslint-disable no-console */
import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { to6Decimals, getTokens } from './utils/common-helpers';
import { cTokenToUnderlying, WAD } from './utils/compound-helpers';

describe('PositionsManagerForCompound Contract', () => {
  // Tokens
  let daiToken: Contract;
  let uniToken: Contract;
  let usdcToken: Contract;
  let cUsdcToken: Contract;

  // Contracts
  let positionsManagerForCompound: Contract;
  let marketsManagerForCompound: Contract;
  let fakeCompoundPositionsManager: Contract;
  let comptroller: Contract;
  let compoundOracle: Contract;
  let priceOracle: Contract;

  // Signers
  let signers: Signer[];
  let owner: Signer;
  let liquidator: Signer;
  let alice: Signer;
  let aliceAddress: string;

  const initialize = async () => {
    // Signers
    signers = await ethers.getSigners();
    [owner, liquidator, alice] = signers;
    aliceAddress = await alice.getAddress();

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
    comptroller = await ethers.getContractAt(require(config.compound.comptroller.abi), config.compound.comptroller.address, owner);
    compoundOracle = await ethers.getContractAt(require(config.compound.oracle.abi), comptroller.oracle(), owner);

    // Mint some tokens
    daiToken = await getTokens(config.tokens.dai.whale, 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
    usdcToken = await getTokens(config.tokens.usdc.whale, 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    uniToken = await getTokens(config.tokens.uni.whale, 'whale', signers, config.tokens.uni, utils.parseUnits('100'));

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
      let smallDaiBorrower;

      for (let i = 0; i < NMAX; i++) {
        console.log('addSmallDaiBorrowers', i);

        smallDaiBorrower = ethers.Wallet.createRandom().address;

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
    let smallDaiSupplier;

    for (let i = 0; i < NMAX; i++) {
      console.log('addSmallDaiSuppliers', i);

      smallDaiSupplier = ethers.Wallet.createRandom().address;
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
    let treeDaiSupplier;

    for (let i = 0; i < NMAX; i++) {
      console.log('addTreeDaiSuppliers', i);
      treeDaiSupplier = ethers.Wallet.createRandom().address;

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [treeDaiSupplier],
      });

      const supplier = await ethers.getSigner(treeDaiSupplier);

      await hre.network.provider.send('hardhat_setBalance', [treeDaiSupplier, utils.hexValue(utils.parseUnits('1000'))]);
      await daiToken.connect(whaleDai).transfer(treeDaiSupplier, daiAmount);

      await daiToken.connect(supplier).approve(positionsManagerForCompound.address, daiAmount);
      await positionsManagerForCompound.connect(supplier).supply(config.tokens.cDai.address, daiAmount);

      // They also borrow Uni so they are matched with alice's collateral
      const UniPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUni.address);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const maxToBorrow = daiAmount.div(UniPriceMantissa).mul(collateralFactorMantissa);

      await positionsManagerForCompound.connect(supplier).borrow(config.tokens.cUni.address, maxToBorrow);
    }
  };

  describe('Worst case scenario for NMAX estimation', () => {
    const NMAX = 24;
    const daiAmountAlice = utils.parseUnits('5000'); // 2*NMAX*SuppliedPerUser

    it('Set new NMAX', async () => {
      expect(await positionsManagerForCompound.NMAX()).to.equal(20);
      await marketsManagerForCompound.connect(owner).setNMAX(NMAX);
      expect(await positionsManagerForCompound.NMAX()).to.equal(NMAX);
    });

    // We have some borrowers that are taking some DAI and supplying as collateral USDC
    it('Add small Dai borrowers', async () => {
      await addSmallDaiBorrowers(NMAX);
    });

    // We have some DAI supplier. They are matched with previous Dai borrowers.
    // We have NMAX match for the DAI market.
    it('Add small Dai Suppliers', async () => {
      await addSmallDaiSuppliers(NMAX);
    });

    // Now, comes other DAI Supplier, that are supplying a greater amount.
    // Also, they borrow some UNI.
    it('Add Tree Dai Suppliers', async () => {
      await addTreeDaiSuppliers(NMAX);
    });

    // Now comes alice, he supplies UNI and his collateral is matched with the NMAX 'Tree Dai Supplier' that are borrowing it.
    // alice also borrows a large quantity of DAI, so that his dai comes from the NMAX 'Tree Dai Supplier'
    it('Add alice', async () => {
      const whaleUni = await ethers.getSigner(config.tokens.uni.whale);
      await uniToken.connect(whaleUni).transfer(aliceAddress, daiAmountAlice.mul(100));
      await uniToken.connect(alice).approve(positionsManagerForCompound.address, daiAmountAlice.mul(100));
      await positionsManagerForCompound.connect(alice).supply(config.tokens.cUni.address, daiAmountAlice.mul(100));
      await positionsManagerForCompound.connect(alice).borrow(config.tokens.cDai.address, daiAmountAlice);
    });

    // Now alice decides to leave Morpho, so she proceeds to a repay and a withdraw of her funds.
    it('alice leaves', async () => {
      await daiToken.connect(alice).approve(positionsManagerForCompound.address, daiAmountAlice.mul(4));
      await positionsManagerForCompound.connect(alice).repay(config.tokens.cDai.address, daiAmountAlice);
      await positionsManagerForCompound.connect(alice).withdraw(config.tokens.cUni.address, utils.parseUnits('19900'));
    });
  });

  describe('Specific case of liquidation with NMAX', () => {
    it('Re initialize', async () => {
      await initialize();
    });

    const NMAX = 24;
    const usdcCollateralAmount = to6Decimals(utils.parseUnits('10000'));
    let daiBorrowAmount: BigNumber;
    let admin: Signer;

    it('Set new NMAX', async () => {
      await marketsManagerForCompound.connect(owner).setNMAX(NMAX);
      expect(await positionsManagerForCompound.NMAX()).to.equal(NMAX);
    });

    it('Setup admin', async () => {
      const adminAddress = await comptroller.admin();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      admin = await ethers.getSigner(adminAddress);
    });

    // First step. alice comes and borrows 'daiBorrowAmount' while putting in collateral 'usdcCollateralAmount'

    // Second step. 2*NMAX suppliers are going to be matched with her debt.
    // (2*NMAX because in the liquidation we have a max liquidation of 50%)

    // Third step. 2*NMAX borrowers comes and are match with the collateral.

    // Fourth step. There is a price variation.

    // Fifth step. alice is liquidated 50%, generating NMAX unmatch of supplier and borrower.

    it('First step, alice comes', async () => {
      const whaleUsdc = await ethers.getSigner(config.tokens.usdc.whale);
      await usdcToken.connect(whaleUsdc).transfer(aliceAddress, usdcCollateralAmount);

      await usdcToken.connect(alice).approve(positionsManagerForCompound.address, usdcCollateralAmount);
      await positionsManagerForCompound.connect(alice).supply(config.tokens.cUsdc.address, usdcCollateralAmount);
      const collateralBalanceInCToken = (await positionsManagerForCompound.supplyBalanceInOf(config.tokens.cUsdc.address, aliceAddress))
        .onPool;
      const cTokenExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cTokenExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cUsdc.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      daiBorrowAmount = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(WAD);
      await positionsManagerForCompound.connect(alice).borrow(config.tokens.cDai.address, daiBorrowAmount);
    });

    it('Second step, add 2*NMAX Dai suppliers', async () => {
      const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
      const daiAmount = daiBorrowAmount.div(2 * NMAX);
      let smallDaiSupplier;

      for (let i = 0; i < 2 * NMAX; i++) {
        console.log('add Dai Suppliers', i);

        smallDaiSupplier = ethers.Wallet.createRandom().address;
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
    });

    it('third step, add 2*NMAX Usdc borrowers', async () => {
      const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
      const usdcAmount = usdcCollateralAmount.div(2 * NMAX);
      const daiAmount = utils.parseUnits(usdcAmount.mul(2).div(1e6).toString());
      let smallUsdcBorrower;

      for (let i = 0; i < 2 * NMAX; i++) {
        console.log('addsmallUsdcBorrowers', i);

        smallUsdcBorrower = ethers.Wallet.createRandom().address;

        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallUsdcBorrower],
        });

        const borrower = await ethers.getSigner(smallUsdcBorrower);

        await hre.network.provider.send('hardhat_setBalance', [smallUsdcBorrower, utils.hexValue(utils.parseUnits('1000'))]);
        await daiToken.connect(whaleDai).transfer(smallUsdcBorrower, daiAmount);

        await daiToken.connect(borrower).approve(positionsManagerForCompound.address, daiAmount);
        await positionsManagerForCompound.connect(borrower).supply(config.tokens.cDai.address, daiAmount);
        await positionsManagerForCompound.connect(borrower).borrow(config.tokens.cUsdc.address, usdcAmount);
      }
    });

    it('Fourth & fifth steps, price variation & liquidation', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('contracts/compound/test/SimplePriceOracle.sol:SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      await comptroller.connect(admin)._setPriceOracle(priceOracle.address);
      const usdcPrice = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      await priceOracle.setUnderlyingPrice(config.tokens.cUsdc.address, usdcPrice);
      await priceOracle.setUnderlyingPrice(config.tokens.cDai.address, BigNumber.from('1020182920000000000'));
      await priceOracle.setUnderlyingPrice(config.tokens.cUni.address, BigNumber.from('1000000000000000000000000000000'));
      await priceOracle.setUnderlyingPrice(config.tokens.cUsdt.address, BigNumber.from('1000000000000000000000000000000'));

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate alice
      const toRepay = daiBorrowAmount.div(2);
      await daiToken.connect(liquidator).approve(positionsManagerForCompound.address, toRepay);
      await positionsManagerForCompound
        .connect(liquidator)
        .liquidate(config.tokens.cDai.address, config.tokens.cUsdc.address, aliceAddress, toRepay);
    });
  });
});
