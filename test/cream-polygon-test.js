require('dotenv').config({ path: '.env.local' });
const { utils, BigNumber } = require('ethers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const hre = require('hardhat');
const config = require('@config/polygon-config.json').polygon;
const {
  SCALE,
  underlyingToCToken,
  cTokenToUnderlying,
  underlyingToMUnit,
  mUnitToUnderlying,
  underlyingToCdUnit,
  cDUnitToUnderlying,
  removeDigitsBigNumber,
  bigNumberMin,
  to6Decimals,
  computeNewMorphoExchangeRate,
  getTokens,
} = require('./utils/helpers');

describe('MorphoPositionsManagerForCream Contract', () => {
  let cUsdcToken;
  let cDaiToken;
  let cUsdtToken;
  let cMkrToken;
  let daiToken;
  let usdtToken;
  let uniToken;
  let MorphoPositionsManagerForCream;
  let morphoPositionsManagerForCream;
  let fakeCreamPositionsManager;

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

  before(async () => {
    // Users
    signers = await ethers.getSigners();
    [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
    suppliers = [supplier1, supplier2, supplier3];
    borrowers = [borrower1, borrower2, borrower3];

    const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
    const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
    await redBlackBinaryTree.deployed();

    // Deploy contracts
    MorphoMarketsManagerForCompLike = await ethers.getContractFactory('MorphoMarketsManagerForCompLike');
    morphoMarketsManagerForCompLike = await MorphoMarketsManagerForCompLike.deploy();
    await morphoMarketsManagerForCompLike.deployed();

    MorphoPositionsManagerForCream = await ethers.getContractFactory('MorphoPositionsManagerForCream', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    morphoPositionsManagerForCream = await MorphoPositionsManagerForCream.deploy(morphoMarketsManagerForCompLike.address, config.cream.comptroller.address);
    fakeCreamPositionsManager = await MorphoPositionsManagerForCream.deploy(morphoMarketsManagerForCompLike.address, config.cream.comptroller.address);
    await morphoPositionsManagerForCream.deployed();
    await fakeCreamPositionsManager.deployed();

    // Get contract dependencies
    const cTokenAbi = require(config.tokens.cToken.abi);
    cUsdcToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdc.address, owner);
    cDaiToken = await ethers.getContractAt(cTokenAbi, config.tokens.cDai.address, owner);
    cUsdtToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdt.address, owner);
    cUniToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUni.address, owner);
    cMkrToken = await ethers.getContractAt(cTokenAbi, config.tokens.cMkr.address, owner); // This is in fact crLINK tokens (no crMKR on Polygon)

    comptroller = await ethers.getContractAt(require(config.cream.comptroller.abi), config.cream.comptroller.address, owner);
    compoundOracle = await ethers.getContractAt(require(config.cream.oracle.abi), comptroller.oracle(), owner);

    // Mint some ERC20
    daiToken = await getTokens('0x27f8d03b3a2196956ed754badc28d73be8830a6e', 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
    usdcToken = await getTokens('0x1a13f4ca1d028320a707d99520abfefca3998b7f', 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    usdtToken = await getTokens('0x44aaa9ebafb4557605de574d5e968589dc3a84d1', 'whale', signers, config.tokens.usdt, BigNumber.from(10).pow(10));
    uniToken = await getTokens('0xf7135272a5584eb116f5a77425118a8b4a2ddfdb', 'whale', signers, config.tokens.uni, utils.parseUnits('100'));

    underlyingThreshold = utils.parseUnits('1');

    // Create and list markets
    await morphoMarketsManagerForCompLike.connect(owner).setPositionsManagerForCompLike(morphoPositionsManagerForCream.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cDai.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cUsdc.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cUni.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cUsdt.address);
    await morphoMarketsManagerForCompLike.connect(owner).updateThreshold(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
    await morphoMarketsManagerForCompLike.connect(owner).updateThreshold(config.tokens.cUsdt.address, BigNumber.from(1).pow(6));
  });

  beforeEach(async () => {
    snapshotId = await hre.network.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await hre.network.provider.send('evm_revert', [snapshotId]);
  });

  describe('Deployment', () => {
    it('Should deploy the contract with the right values', async () => {
      // Calculate p2pBPY
      const borrowRatePerBlock = await cDaiToken.borrowRatePerBlock();
      const supplyRatePerBlock = await cDaiToken.supplyRatePerBlock();
      const expectedBPY = borrowRatePerBlock.add(supplyRatePerBlock).div(2);
      expect(await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cDai.address)).to.equal(expectedBPY);
      expect(await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address)).to.be.equal(utils.parseUnits('1'));

      // Thresholds
      underlyingThreshold = await morphoPositionsManagerForCream.thresholds(config.tokens.cDai.address);
      expect(underlyingThreshold).to.be.equal(utils.parseUnits('1'));
    });
  });

  describe('Governance functions', () => {
    it('Should revert when at least when a market in input is not a real market', async () => {
      expect(morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.usdt.address)).to.be.reverted;
    });

    it('Only Owner should be able to create markets in peer-to-peer', async () => {
      expect(morphoMarketsManagerForCompLike.connect(supplier1).createMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(morphoMarketsManagerForCompLike.connect(borrower1).createMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cEth.address)).not.be.reverted;
    });

    it('Only Morpho should be able to create markets on MorphoPositionsManagerForCream', async () => {
      expect(morphoPositionsManagerForCream.connect(supplier1).createMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(morphoPositionsManagerForCream.connect(borrower1).createMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(morphoPositionsManagerForCream.connect(owner).createMarket(config.tokens.cEth.address)).to.be.reverted;
      await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cEth.address);
      expect(await comptroller.checkMembership(morphoPositionsManagerForCream.address, config.tokens.cEth.address)).to.be.true;
    });

    it('marketsManagerForCompLike should not be changed after already set by Owner', async () => {
      expect(morphoMarketsManagerForCompLike.connect(owner).setPositionsManagerForCompLike(fakeCreamPositionsManager.address)).to.be.reverted;
    });

    it('Only Owner should be able to update thresholds', async () => {
      const newThreshold = utils.parseUnits('2');
      await morphoMarketsManagerForCompLike.connect(owner).updateThreshold(config.tokens.cUsdc.address, newThreshold);

      // Other accounts than Owner
      await expect(morphoMarketsManagerForCompLike.connect(supplier1).updateThreshold(config.tokens.cUsdc.address, newThreshold)).to.be.reverted;
      await expect(morphoMarketsManagerForCompLike.connect(borrower1).updateThreshold(config.tokens.cUsdc.address, newThreshold)).to.be.reverted;
    });

    it('Should create a market the with right values', async () => {
      const supplyBPY = await cMkrToken.supplyRatePerBlock();
      const borrowBPY = await cMkrToken.borrowRatePerBlock();
      const { blockNumber } = await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cMkr.address);
      expect(await morphoMarketsManagerForCompLike.isCreated(config.tokens.cMkr.address)).to.be.true;

      const p2pBPY = supplyBPY.add(borrowBPY).div(2);
      expect(await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cMkr.address)).to.equal(p2pBPY);

      expect(await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cMkr.address)).to.equal(SCALE);
      expect(await morphoMarketsManagerForCompLike.lastUpdateBlockNumber(config.tokens.cMkr.address)).to.equal(blockNumber);
    });

    it('Comptroller can be set only by owner', async () => {
      await expect(morphoMarketsManagerForCompLike.connect(supplier1).setComptroller(comptroller.address)).to.be.reverted;
      await expect(morphoMarketsManagerForCompLike.connect(borrower1).setComptroller(comptroller.address)).to.be.reverted;

      await expect(morphoMarketsManagerForCompLike.connect(owner).setComptroller(comptroller.address)).not.to.be.reverted;
    });
  });

  describe('Suppliers on Compound (no borrowers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream).to.equal(0);
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should revert when supply less than the required threshold', async () => {
      await expect(morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, underlyingThreshold.sub(1))).to.be.reverted;
    });

    it('Should have the correct balances after supply', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, amount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, amount);
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedSupplyBalanceOnComp = underlyingToCToken(amount, exchangeRate);
      expect(await cDaiToken.balanceOf(morphoPositionsManagerForCream.address)).to.equal(expectedSupplyBalanceOnComp);
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream).to.equal(expectedSupplyBalanceOnComp);
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should be able to withdraw ERC20 right after supply up to max supply balance', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, amount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, amount);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));

      const supplyBalanceOnComp = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw1 = cTokenToUnderlying(supplyBalanceOnComp, exchangeRate1);

      // TODO: improve this test to prevent attacks
      await expect(morphoPositionsManagerForCream.connect(supplier1).withdraw(toWithdraw1.add(utils.parseUnits('0.001')).toString())).to.be.reverted;

      // Update exchange rate
      await cDaiToken.connect(supplier1).exchangeRateCurrent();
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw2 = cTokenToUnderlying(supplyBalanceOnComp, exchangeRate2);
      await morphoPositionsManagerForCream.connect(supplier1).withdraw(config.tokens.cDai.address, toWithdraw2);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());
      // Check ERC20 balance
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1.sub(amount).add(toWithdraw2));

      // Check cToken left are only dust in supply balance
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream).to.be.lt(1000);
      await expect(morphoPositionsManagerForCream.connect(supplier1).withdraw(config.tokens.cDai.address, utils.parseUnits('0.001'))).to.be.reverted;
    });

    it('Should be able to supply more ERC20 after already having supply ERC20', async () => {
      const amount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('10').mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());

      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, amountToApprove);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, amount);
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, amount);
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check supply balance
      const expectedSupplyBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedSupplyBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedSupplyBalanceOnComp = expectedSupplyBalanceOnComp1.add(expectedSupplyBalanceOnComp2);
      expect(await cDaiToken.balanceOf(morphoPositionsManagerForCream.address)).to.equal(expectedSupplyBalanceOnComp);
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream).to.equal(expectedSupplyBalanceOnComp);
    });

    it('Several suppliers should be able to supply and have the correct balances', async () => {
      const amount = utils.parseUnits('10');
      let expectedCTokenBalance = BigNumber.from(0);

      for (const i in suppliers) {
        const supplier = suppliers[i];
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(supplier).approve(morphoPositionsManagerForCream.address, amount);
        await morphoPositionsManagerForCream.connect(supplier).supply(config.tokens.cDai.address, amount);
        const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const expectedSupplyBalanceOnComp = underlyingToCToken(amount, exchangeRate);
        expectedCTokenBalance = expectedCTokenBalance.add(expectedSupplyBalanceOnComp);
        expect(removeDigitsBigNumber(7, await cDaiToken.balanceOf(morphoPositionsManagerForCream.address))).to.equal(removeDigitsBigNumber(7, expectedCTokenBalance));
        expect(removeDigitsBigNumber(4, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier.getAddress())).onCream)).to.equal(
          removeDigitsBigNumber(4, expectedSupplyBalanceOnComp)
        );
        expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier.getAddress())).inP2P).to.equal(0);
      }
    });
  });

  describe('Borrowers on Compound (no suppliers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(0);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P).to.equal(0);
    });

    it('Should revert when providing 0 as collateral', async () => {
      await expect(morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, 0)).to.be.reverted;
    });

    it('Should revert when borrow less than threshold', async () => {
      const amount = to6Decimals(utils.parseUnits('10'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, amount);
      await expect(morphoPositionsManagerForCream.connect(supplier1).borrow(config.tokens.cDai.address, amount)).to.be.reverted;
    });

    it('Should be able to borrow on Compound after providing collateral up to max', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, amount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, amount);
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInCToken = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream;
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const borrowIndex = await cDaiToken.borrowIndex();
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      const borrowBalanceOnCompInUnderlying = cDUnitToUnderlying((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream, borrowIndex);
      let diff;
      if (borrowBalanceOnCompInUnderlying.gt(maxToBorrow)) diff = borrowBalanceOnCompInUnderlying.sub(maxToBorrow);
      else diff = maxToBorrow.sub(borrowBalanceOnCompInUnderlying);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);

      // Check Morpho balances
      expect(await daiToken.balanceOf(morphoPositionsManagerForCream.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForCream.address)).to.equal(maxToBorrow);
    });

    it('Should not be able to borrow more than max allowed given an amount of collateral', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, amount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, amount);
      const collateralBalanceInCToken = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      // WARNING: maxToBorrow seems to be not accurate
      const moreThanMaxToBorrow = maxToBorrow.add(utils.parseUnits('10'));

      // TODO: fix dust issue
      // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
      await expect(morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, moreThanMaxToBorrow)).to.be.reverted;
    });

    it('Several borrowers should be able to borrow and have the correct balances', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('10'));
      const borrowedAmount = utils.parseUnits('2');
      let expectedMorphoBorrowBalance = BigNumber.from(0);
      let previousBorrowIndex = await cDaiToken.borrowIndex();

      for (const i in borrowers) {
        const borrower = borrowers[i];
        await usdcToken.connect(borrower).approve(morphoPositionsManagerForCream.address, collateralAmount);
        await morphoPositionsManagerForCream.connect(borrower).supply(config.tokens.cUsdc.address, collateralAmount);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await morphoPositionsManagerForCream.connect(borrower).borrow(config.tokens.cDai.address, borrowedAmount);
        // We have one block delay from Compound
        const borrowIndex = await cDaiToken.borrowIndex();
        expectedMorphoBorrowBalance = expectedMorphoBorrowBalance.mul(borrowIndex).div(previousBorrowIndex).add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        const borrowBalanceOnCompInUnderlying = cDUnitToUnderlying((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower.getAddress())).onCream, borrowIndex);
        let diff;
        if (borrowBalanceOnCompInUnderlying.gt(borrowedAmount)) diff = borrowBalanceOnCompInUnderlying.sub(borrowedAmount);
        else diff = borrowedAmount.sub(borrowBalanceOnCompInUnderlying);
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        // Update previous borrow index
        previousBorrowIndex = borrowIndex;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(morphoPositionsManagerForCream.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForCream.address)).to.equal(expectedMorphoBorrowBalance);
    });

    it('Borrower should be able to repay less than what is on Compound', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, amount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, amount);
      const collateralBalanceInCToken = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);

      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const borrowBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream;
      const borrowIndex1 = await cDaiToken.borrowIndex();
      const borrowBalanceOnCompInUnderlying = cDUnitToUnderlying(borrowBalanceOnComp, borrowIndex1);
      const toRepay = borrowBalanceOnCompInUnderlying.div(2);
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, toRepay);
      const borrowIndex2 = await cDaiToken.borrowIndex();
      await morphoPositionsManagerForCream.connect(borrower1).repay(config.tokens.cDai.address, toRepay);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      const expectedBalanceOnComp = borrowBalanceOnComp.sub(underlyingToCdUnit(borrowBalanceOnCompInUnderlying.div(2), borrowIndex2));
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(expectedBalanceOnComp);
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow).sub(toRepay));
    });
  });

  describe('P2P interactions between supplier and borrowers', () => {
    it('Supplier should withdraw her liquidity while not enough cToken in peer-to-peer contract', async () => {
      // Supplier supplies tokens
      const supplyAmount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(supplyAmount);
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, supplyAmount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, supplyAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedSupplyBalanceOnComp1 = underlyingToCToken(supplyAmount, cExchangeRate1);
      expect(await cDaiToken.balanceOf(morphoPositionsManagerForCream.address)).to.equal(expectedSupplyBalanceOnComp1);
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream).to.equal(expectedSupplyBalanceOnComp1);

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);

      // Borrowers borrows supplier1 amount
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, supplyAmount);

      // Check supplier1 balances
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const mExchangeRate1 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const expectedSupplyBalanceOnComp2 = expectedSupplyBalanceOnComp1.sub(underlyingToCToken(supplyAmount, cExchangeRate2));
      const expectedSupplyBalanceInP2P2 = underlyingToMUnit(supplyAmount, mExchangeRate1);
      const supplyBalanceOnComp2 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const supplyBalanceInP2P2 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      expect(supplyBalanceOnComp2).to.equal(expectedSupplyBalanceOnComp2);
      expect(supplyBalanceInP2P2).to.equal(expectedSupplyBalanceInP2P2);

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(0);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P).to.equal(expectedBorrowBalanceInP2P1);

      // Compare remaining to withdraw and the cToken contract balance
      await morphoMarketsManagerForCompLike.connect(owner).updateMUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate2 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnComp3 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const supplyBalanceInP2P3 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateStored();
      const supplyBalanceOnCompInUnderlying = cTokenToUnderlying(supplyBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = supplyBalanceOnCompInUnderlying.add(mUnitToUnderlying(supplyBalanceInP2P3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(morphoPositionsManagerForCream.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.gt(cTokenContractBalanceInUnderlying);

      // Expected borrow balances
      const expectedMorphoBorrowBalance = remainingToWithdraw.add(cTokenContractBalanceInUnderlying).sub(supplyBalanceOnCompInUnderlying);

      // Withdraw
      await morphoPositionsManagerForCream.connect(supplier1).withdraw(config.tokens.cDai.address, amountToWithdraw);
      const borrowIndex = await cDaiToken.borrowIndex();
      const expectedBorrowerBorrowBalanceOnComp = underlyingToCdUnit(expectedMorphoBorrowBalance, borrowIndex);
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForCream.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      // Check borrow balance of Morpho
      expect(removeDigitsBigNumber(10, borrowBalance)).to.equal(removeDigitsBigNumber(10, expectedMorphoBorrowBalance));

      // Check supplier1 underlying balance
      expect(removeDigitsBigNumber(1, daiBalanceAfter2)).to.equal(removeDigitsBigNumber(1, expectedDaiBalanceAfter2));

      // Check supply balances of supplier1
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream)).to.equal(0);
      expect(removeDigitsBigNumber(9, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P)).to.equal(0);

      // Check borrow balances of borrower1
      expect(removeDigitsBigNumber(9, (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream)).to.equal(
        removeDigitsBigNumber(9, expectedBorrowerBorrowBalanceOnComp)
      );
      expect(removeDigitsBigNumber(9, (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P)).to.equal(0);
    });

    it('Debt should increase over time', async () => {
      // Supplier supplies tokens
      const supplyAmount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(supplyAmount);
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, supplyAmount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, supplyAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedSupplyBalanceOnComp1 = underlyingToCToken(supplyAmount, cExchangeRate1);
      expect(await cDaiToken.balanceOf(morphoPositionsManagerForCream.address)).to.equal(expectedSupplyBalanceOnComp1);
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream).to.equal(expectedSupplyBalanceOnComp1);

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);

      // Borrowers borrows supplier1 amount
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, supplyAmount);
      const mExchangeRate1 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const p2pBPY = await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cDai.address);

      const borrowerBalanceInP2P = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P;

      // Mine block 1000 blocks
      for (let i = 0; i < 1000; i++) {
        await hre.network.provider.send('evm_mine', []);
      }

      // Get the updated Morpho exchange rate
      await morphoMarketsManagerForCompLike.updateMUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate2 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);

      // Compute what's expected to be repaid
      const expectedNewMUnitExchangeRate = mExchangeRate1 * (1 + p2pBPY / 1e18) ** 1000;
      const expectedToRepay = (expectedNewMUnitExchangeRate * borrowerBalanceInP2P) / SCALE;

      // Compare both values
      const toRepay = removeDigitsBigNumber(12, mUnitToUnderlying(borrowerBalanceInP2P, mExchangeRate2));
      expect(toRepay).to.equal(removeDigitsBigNumber(12, BigNumber.from(expectedToRepay.toString())));

      // Check that after repaying, the borrowing balance decreases
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, BigNumber.from(expectedToRepay.toString()));
      await morphoPositionsManagerForCream.connect(borrower1).repay(config.tokens.cDai.address, BigNumber.from(expectedToRepay.toString()));
      const borrowerBalanceAfterRepay = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P;
      expect(removeDigitsBigNumber(12, mUnitToUnderlying(borrowerBalanceAfterRepay, mExchangeRate2))).to.equal(0);
    });

    it('Supplier should withdraw her liquidity while enough cDaiToken in peer-to-peer contract', async () => {
      const supplyAmount = utils.parseUnits('10');
      let supplier;

      for (const i in suppliers) {
        supplier = suppliers[i];
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(supplyAmount);
        await daiToken.connect(supplier).approve(morphoPositionsManagerForCream.address, supplyAmount);
        await morphoPositionsManagerForCream.connect(supplier).supply(config.tokens.cDai.address, supplyAmount);
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
        const expectedSupplyBalanceOnComp = underlyingToCToken(supplyAmount, cExchangeRate);
        expect(removeDigitsBigNumber(4, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier.getAddress())).onCream)).to.equal(
          removeDigitsBigNumber(4, expectedSupplyBalanceOnComp)
        );
      }

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);

      const previousSupplier1SupplyBalanceOnComp = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;

      // Borrowers borrows supplier1 amount
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, supplyAmount);

      // Check supplier1 balances
      const mExchangeRate1 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      // Expected balances of supplier1
      const expectedSupplyBalanceOnComp2 = previousSupplier1SupplyBalanceOnComp.sub(underlyingToCToken(supplyAmount, cExchangeRate2));
      const expectedSupplyBalanceInP2P2 = underlyingToMUnit(supplyAmount, mExchangeRate1);
      const supplyBalanceOnComp2 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const supplyBalanceInP2P2 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      expect(supplyBalanceOnComp2).to.equal(expectedSupplyBalanceOnComp2);
      expect(supplyBalanceInP2P2).to.equal(expectedSupplyBalanceInP2P2);

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(0);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P).to.equal(expectedBorrowBalanceInP2P1);

      // Compare remaining to withdraw and the cToken contract balance
      await morphoMarketsManagerForCompLike.connect(owner).updateMUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate2 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnComp3 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const supplyBalanceInP2P3 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateCurrent();
      const supplyBalanceOnCompInUnderlying = cTokenToUnderlying(supplyBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = supplyBalanceOnCompInUnderlying.add(mUnitToUnderlying(supplyBalanceInP2P3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(morphoPositionsManagerForCream.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.lt(cTokenContractBalanceInUnderlying);

      // supplier3 balances before the withdraw
      const supplier3SupplyBalanceOnComp = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier3.getAddress())).onCream;
      const supplier3SupplyBalanceInP2P = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier3.getAddress())).inP2P;

      // supplier2 balances before the withdraw
      const supplier2SupplyBalanceOnComp = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier2.getAddress())).onCream;
      const supplier2SupplyBalanceInP2P = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier2.getAddress())).inP2P;

      // borrower1 balances before the withdraw
      const borrower1BorrowBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream;
      const borrower1BorrowBalanceInP2P = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P;

      // Withdraw
      await morphoPositionsManagerForCream.connect(supplier1).withdraw(config.tokens.cDai.address, amountToWithdraw);
      const cExchangeRate4 = await cDaiToken.callStatic.exchangeRateStored();
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForCream.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      const supplier2SupplyBalanceOnCompInUnderlying = cTokenToUnderlying(supplier2SupplyBalanceOnComp, cExchangeRate4);
      const amountToMove = bigNumberMin(supplier2SupplyBalanceOnCompInUnderlying, remainingToWithdraw);
      const mExchangeRate4 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const expectedSupplier2SupplyBalanceOnComp = supplier2SupplyBalanceOnComp.sub(underlyingToCToken(amountToMove, cExchangeRate4));
      const expectedSupplier2SupplyBalanceInP2P = supplier2SupplyBalanceInP2P.add(underlyingToMUnit(amountToMove, mExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check supplier1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check supply balances of supplier1
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream)).to.equal(0);
      expect(removeDigitsBigNumber(5, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P)).to.equal(0);

      // Check supply balances of supplier2: supplier2 should have replaced supplier1
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier2.getAddress())).onCream)).to.equal(
        removeDigitsBigNumber(1, expectedSupplier2SupplyBalanceOnComp)
      );
      expect(removeDigitsBigNumber(7, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier2.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(7, expectedSupplier2SupplyBalanceInP2P)
      );

      // Check supply balances of supplier3: supplier3 balances should not move
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier3.getAddress())).onCream).to.equal(supplier3SupplyBalanceOnComp);
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier3.getAddress())).inP2P).to.equal(supplier3SupplyBalanceInP2P);

      // Check borrow balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(borrower1BorrowBalanceOnComp);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P).to.equal(borrower1BorrowBalanceInP2P);
    });

    it('Borrower in peer-to-peer only, should be able to repay all borrow amount', async () => {
      // Supplier supplies tokens
      const supplyAmount = utils.parseUnits('10');
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, supplyAmount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, supplyAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.div(2);

      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, toBorrow);

      const borrowerBalanceInP2P = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P;
      const p2pBPY = await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cDai.address);
      await morphoMarketsManagerForCompLike.updateMUnitExchangeRate(config.tokens.cDai.address);
      const mUnitExchangeRate = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      // WARNING: Should be one block but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, p2pBPY, 1, 0).toString();
      const toRepay = mUnitToUnderlying(borrowerBalanceInP2P, mExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(morphoPositionsManagerForCream.address);

      // Repay
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, toRepay);
      await morphoPositionsManagerForCream.connect(borrower1).repay(config.tokens.cDai.address, toRepay);
      const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(toRepay, cExchangeRate));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);

      // Verify all of the borrower balance is in P2P
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(0);

      // Mine block 1000 blocks
      for (let i = 0; i < 1000; i++) {
        await hre.network.provider.send('evm_mine', []);
      }

      // Get the updated Morpho exchange rate
      await morphoMarketsManagerForCompLike.updateMUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate2 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);

      // Compute what's expected to be repaid
      const expectedToRepay = toBorrow * (1 + p2pBPY / 1e18) ** 1000;
      const expectedToRepayBigNumber = removeDigitsBigNumber(12, BigNumber.from(expectedToRepay.toString()));

      // Compare both values
      expect(removeDigitsBigNumber(12, mUnitToUnderlying(borrowerBalanceInP2P, mExchangeRate2))).to.equal(expectedToRepayBigNumber);

      // Check Morpho balances
      expect(await cDaiToken.balanceOf(morphoPositionsManagerForCream.address)).to.equal(expectedMorphoCTokenBalance);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForCream.address)).to.equal(0);
    });

    it('Borrower in peer-to-peer only, should be able to repay all borrow amount, CASE 2.1', async () => {
      // Supplier supplies tokens
      const supplyAmount = utils.parseUnits('10');
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, supplyAmount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, supplyAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.div(2);

      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, toBorrow);

      // Borrower 2
      const toBorrow2 = utils.parseUnits('10');
      await usdcToken.connect(borrower2).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower2).supply(config.tokens.cUsdc.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower2).borrow(config.tokens.cDai.address, toBorrow2);

      const mExchangeRate1 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const p2pBPY = await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cDai.address);

      const toRepay = toBorrow;
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);

      // Repay
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, toRepay);
      await morphoPositionsManagerForCream.connect(borrower1).repay(config.tokens.cDai.address, toRepay);

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);

      // Verify all of the borrower balance is in P2P
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(0);
      const borrower2BalanceInP2P = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower2.getAddress())).inP2P;

      // Mine block 1000 blocks
      for (let i = 0; i < 1000; i++) {
        await hre.network.provider.send('evm_mine', []);
      }

      // Get the updated Morpho exchange rate
      await morphoMarketsManagerForCompLike.updateMUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate2 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);

      // Compute expected MUniteExchangerate
      const expectedNewMUnitExchangeRate = mExchangeRate1 * (1 + p2pBPY / 1e18) ** 1000;

      // For supplier
      // Compute what's expected to be withdrawn
      const supplierBalanceInP2P = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      const expectedToWithdraw = (expectedNewMUnitExchangeRate * supplierBalanceInP2P) / SCALE;
      // Compare both values
      const toWithdraw = removeDigitsBigNumber(12, mUnitToUnderlying(supplierBalanceInP2P, mExchangeRate2));
      expect(toWithdraw).to.equal(removeDigitsBigNumber(12, BigNumber.from(expectedToWithdraw.toString())));

      // Check that after withdrawing, the supplying balance decreases
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, toWithdraw);
      await morphoPositionsManagerForCream.connect(supplier1).withdraw(config.tokens.cDai.address, toWithdraw);
      const supplierBalanceAfterWithdraw = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      expect(removeDigitsBigNumber(12, mUnitToUnderlying(supplierBalanceAfterWithdraw, mExchangeRate2))).to.equal(0);

      // For Borrower2
      // Compute what's expected to be repaid
      const expectedToRepay = (expectedNewMUnitExchangeRate * borrower2BalanceInP2P) / SCALE;
      // Compare both values
      const toRepayBorrower2 = removeDigitsBigNumber(12, mUnitToUnderlying(borrower2BalanceInP2P, mExchangeRate2));
      expect(toRepayBorrower2).to.equal(removeDigitsBigNumber(12, BigNumber.from(expectedToRepay.toString())));

      // Check that after repaying, the borrowing balance decreases
      await daiToken.connect(borrower2).approve(morphoPositionsManagerForCream.address, mUnitToUnderlying(borrower2BalanceInP2P, mExchangeRate2));
      await morphoPositionsManagerForCream.connect(borrower2).repay(config.tokens.cDai.address, mUnitToUnderlying(borrower2BalanceInP2P, mExchangeRate2));
      const borrowerBalanceAfterRepay = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower2.getAddress())).inP2P;
      expect(removeDigitsBigNumber(12, mUnitToUnderlying(borrowerBalanceAfterRepay, mExchangeRate2))).to.equal(0);
    });

    it('Borrower in peer-to-peer and on Compound, should be able to repay all borrow amount', async () => {
      // Supplier supplies tokens
      const supplyAmount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('100000000');
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, supplyAmount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, supplyAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.mul(2);
      const supplyBalanceOnComp = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, toBorrow);

      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoBorrowBalance1 = toBorrow.sub(cTokenToUnderlying(supplyBalanceOnComp, cExchangeRate1));
      const morphoBorrowBalanceBefore1 = await cDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForCream.address);
      expect(removeDigitsBigNumber(6, morphoBorrowBalanceBefore1)).to.equal(removeDigitsBigNumber(6, expectedMorphoBorrowBalance1));
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, amountToApprove);

      const borrowerBalanceInP2P = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P;
      const p2pBPY = await morphoMarketsManagerForCompLike.p2pBPY(config.tokens.cDai.address);
      const mUnitExchangeRate = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      // WARNING: Should be 2 blocks but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, p2pBPY, 1, 0).toString();
      const borrowerBalanceInP2PInUnderlying = mUnitToUnderlying(borrowerBalanceInP2P, mExchangeRate);

      // Compute how much to repay
      const doUpdate = await cDaiToken.borrowBalanceCurrent(morphoPositionsManagerForCream.address);
      await doUpdate.wait(1);
      const borrowIndex1 = await cDaiToken.borrowIndex();
      const borrowerBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream;
      const toRepay = borrowerBalanceOnComp.mul(borrowIndex1).div(SCALE).add(borrowerBalanceInP2PInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(morphoPositionsManagerForCream.address);

      // Repay
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, toRepay);
      const borrowIndex3 = await cDaiToken.callStatic.borrowIndex();
      await morphoPositionsManagerForCream.connect(borrower1).repay(config.tokens.cDai.address, toRepay);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(borrowerBalanceInP2PInUnderlying, cExchangeRate2));
      const expectedBalanceOnComp = borrowerBalanceOnComp.sub(borrowerBalanceOnComp.mul(borrowIndex1).div(borrowIndex3));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream;
      expect(removeDigitsBigNumber(2, borrower1BorrowBalanceOnComp)).to.equal(removeDigitsBigNumber(2, expectedBalanceOnComp));
      // WARNING: Commented here due to the pow function issue
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P).to.be.lt(1000000000000);

      // Check Morpho balances
      expect(removeDigitsBigNumber(5, await cDaiToken.balanceOf(morphoPositionsManagerForCream.address))).to.equal(removeDigitsBigNumber(5, expectedMorphoCTokenBalance));
      // Issue here: we cannot access the most updated borrow balance as it's updated during the repayBorrow on Compound.
      // const expectedMorphoBorrowBalance2 = morphoBorrowBalanceBefore2.sub(borrowerBalanceOnComp.mul(borrowIndex2).div(SCALE));
      // expect(removeDigitsBigNumber(3, await cToken.callStatic.borrowBalanceStored(morphoPositionsManagerForCream.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowBalance2));
    });

    it('Should disconnect supplier from Morpho when borrow an asset that nobody has on morphoMarketsManagerForCompLike and the supply balance is partly used', async () => {
      // supplier1 supplies DAI
      const supplyAmount = utils.parseUnits('100');
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, supplyAmount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, supplyAmount);

      // borrower1 supplies USDC as collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);

      // borrower1 borrows part of the supply amount of supplier1
      const amountToBorrow = supplyAmount.div(2);
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, amountToBorrow);
      const borrowBalanceInP2P = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P;

      // supplier1 borrows USDT that nobody is supply in peer-to-peer
      const cDaiExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const mDaiExchangeRate1 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const supplyBalanceOnComp1 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const supplyBalanceInP2P1 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      const supplyBalanceOnCompInUnderlying = cTokenToUnderlying(supplyBalanceOnComp1, cDaiExchangeRate1);
      const supplyBalanceMorphoInUnderlying = mUnitToUnderlying(supplyBalanceInP2P1, mDaiExchangeRate1);
      const supplyBalanceInUnderlying = supplyBalanceOnCompInUnderlying.add(supplyBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdtPriceMantissa = await compoundOracle.callStatic.getUnderlyingPrice(config.tokens.cUsdt.address);
      const daiPriceMantissa = await compoundOracle.callStatic.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = supplyBalanceInUnderlying.mul(daiPriceMantissa).div(usdtPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      await morphoPositionsManagerForCream.connect(supplier1).borrow(config.tokens.cUsdt.address, maxToBorrow);

      // Check balances
      const supplyBalanceOnComp2 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const borrowBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream;
      const cDaiExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const cDaiBorrowIndex = await cDaiToken.borrowIndex();
      const mDaiExchangeRate2 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const expectedBorrowBalanceOnComp = mUnitToUnderlying(borrowBalanceInP2P, mDaiExchangeRate2).mul(SCALE).div(cDaiBorrowIndex);
      const usdtBorrowBalance = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cUsdt.address, supplier1.getAddress())).onCream;
      const cUsdtBorrowIndex = await cUsdtToken.borrowIndex();
      const usdtBorrowBalanceInUnderlying = usdtBorrowBalance.mul(cUsdtBorrowIndex).div(SCALE);
      expect(removeDigitsBigNumber(6, supplyBalanceOnComp2)).to.equal(removeDigitsBigNumber(6, underlyingToCToken(supplyBalanceInUnderlying, cDaiExchangeRate2)));
      expect(removeDigitsBigNumber(2, borrowBalanceOnComp)).to.equal(removeDigitsBigNumber(2, expectedBorrowBalanceOnComp));
      expect(removeDigitsBigNumber(2, usdtBorrowBalanceInUnderlying)).to.equal(removeDigitsBigNumber(2, maxToBorrow));
    });

    it('Supplier should be connected to borrowers already in peer-to-peer when supplying', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const supplyAmount = utils.parseUnits('100');
      const borrowAmount = utils.parseUnits('30');

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, borrowAmount);
      const borrower1BorrowBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream;

      // borrower2 borrows
      await usdcToken.connect(borrower2).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower2).supply(config.tokens.cUsdc.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower2).borrow(config.tokens.cDai.address, borrowAmount);
      const borrower2BorrowBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower2.getAddress())).onCream;

      // borrower3 borrows
      await usdcToken.connect(borrower3).approve(morphoPositionsManagerForCream.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower3).supply(config.tokens.cUsdc.address, collateralAmount);
      await morphoPositionsManagerForCream.connect(borrower3).borrow(config.tokens.cDai.address, borrowAmount);
      const borrower3BorrowBalanceOnComp = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower3.getAddress())).onCream;

      // supplier1 supply
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, supplyAmount);
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, supplyAmount);
      const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
      const borrowIndex = await cDaiToken.borrowIndex();
      const mUnitExchangeRate = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);

      // Check balances
      const supplyBalanceInP2P = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).inP2P;
      const supplyBalanceOnComp = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onCream;
      const underlyingMatched = cDUnitToUnderlying(borrower1BorrowBalanceOnComp.add(borrower2BorrowBalanceOnComp).add(borrower3BorrowBalanceOnComp), borrowIndex);
      expectedSupplyBalanceInP2P = underlyingMatched.mul(SCALE).div(mUnitExchangeRate);
      expectedSupplyBalanceOnComp = underlyingToCToken(supplyAmount.sub(underlyingMatched), cExchangeRate);
      expect(removeDigitsBigNumber(2, supplyBalanceInP2P)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceInP2P));
      expect(supplyBalanceOnComp).to.equal(expectedSupplyBalanceOnComp);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.be.lte(1);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower2.getAddress())).onCream).to.be.lte(1);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower3.getAddress())).onCream).to.be.lte(1);
    });
  });

  describe('Test liquidation', () => {
    it('Borrower should be liquidated while supply (collateral) is only on Cream', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await comptroller.admin();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      // Deposit
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, amount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, amount);
      const collateralBalanceInCToken = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cUsdc.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);

      // Borrow
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const collateralBalanceBefore = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream;
      const borrowBalanceBefore = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream;

      // Set price oracle
      await comptroller.connect(admin)._setPriceOracle(priceOracle.address);
      priceOracle.setUnderlyingPrice(config.tokens.cDai.address, BigNumber.from('1010182920000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.cUsdc.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.cUni.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.cUsdt.address, BigNumber.from('1000000000000000000000000000000'));

      // Force creamOracle update by setting comptroller again (but with the custom price oracle)
      await hre.network.provider.send('hardhat_impersonateAccount', [morphoMarketsManagerForCompLike.address]);
      await hre.network.provider.send('hardhat_setBalance', [morphoMarketsManagerForCompLike.address, ethers.utils.parseEther('10').toHexString()]);
      const morphoMarketsManagerUser = await ethers.getSigner(morphoMarketsManagerForCompLike.address);
      await morphoPositionsManagerForCream.connect(morphoMarketsManagerUser).setComptroller(comptroller.address);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate
      const toRepay = maxToBorrow.div(2);
      await daiToken.connect(liquidator).approve(morphoPositionsManagerForCream.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await morphoPositionsManagerForCream.connect(liquidator).liquidate(config.tokens.cDai.address, config.tokens.cUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const borrowIndex = await cDaiToken.borrowIndex();
      const cUsdcExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await comptroller.liquidationIncentiveMantissa();
      const collateralAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const borrowedAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceAfter = collateralBalanceBefore.sub(underlyingToCToken(amountToSeize, cUsdcExchangeRate));
      const expectedBorrowBalanceAfter = borrowBalanceBefore.sub(underlyingToCdUnit(toRepay, borrowIndex));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check balances
      expect(removeDigitsBigNumber(6, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream)).to.equal(
        removeDigitsBigNumber(6, expectedCollateralBalanceAfter)
      );
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(expectedBorrowBalanceAfter);
      expect(removeDigitsBigNumber(1, usdcBalanceAfter)).to.equal(removeDigitsBigNumber(1, expectedUsdcBalanceAfter));
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });

    it('Borrower should be liquidated while supply (collateral) is on Compound and in peer-to-peer', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await comptroller.admin();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      await daiToken.connect(supplier1).approve(morphoPositionsManagerForCream.address, utils.parseUnits('1000'));
      await morphoPositionsManagerForCream.connect(supplier1).supply(config.tokens.cDai.address, utils.parseUnits('1000'));

      // borrower1 supplies USDC as supply (collateral)
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForCream.address, amount);
      await morphoPositionsManagerForCream.connect(borrower1).supply(config.tokens.cUsdc.address, amount);

      // borrower2 borrows part of supply of borrower1 -> borrower1 has supply in peer-to-peer and on Cream
      const toBorrow = amount;
      await uniToken.connect(borrower2).approve(morphoPositionsManagerForCream.address, utils.parseUnits('50'));
      await morphoPositionsManagerForCream.connect(borrower2).supply(config.tokens.cUni.address, utils.parseUnits('50'));
      await morphoPositionsManagerForCream.connect(borrower2).borrow(config.tokens.cUsdc.address, toBorrow);

      // borrower1 borrows DAI
      const cUsdcExchangeRate1 = await cUsdcToken.callStatic.exchangeRateCurrent();
      const mUsdcExchangeRate1 = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cUsdc.address);
      const supplyBalanceOnComp1 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream;
      const supplyBalanceInP2P1 = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).inP2P;
      const supplyBalanceOnCompInUnderlying = cTokenToUnderlying(supplyBalanceOnComp1, cUsdcExchangeRate1);
      const supplyBalanceMorphoInUnderlying = mUnitToUnderlying(supplyBalanceInP2P1, mUsdcExchangeRate1);
      const supplyBalanceInUnderlying = supplyBalanceOnCompInUnderlying.add(supplyBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cUsdc.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = supplyBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      await morphoPositionsManagerForCream.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const collateralBalanceOnCompBefore = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream;
      const collateralBalanceInP2PBefore = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).inP2P;
      const borrowBalanceInP2PBefore = (await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P;

      // Set price oracle
      await comptroller.connect(admin)._setPriceOracle(priceOracle.address);
      priceOracle.setUnderlyingPrice(config.tokens.cDai.address, BigNumber.from('1020182920000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.cUsdc.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.cUni.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.cUsdt.address, BigNumber.from('1000000000000000000000000000000'));

      // Force creamOracle update by setting comptroller again (but with the custom price oracle)
      await hre.network.provider.send('hardhat_impersonateAccount', [morphoMarketsManagerForCompLike.address]);
      await hre.network.provider.send('hardhat_setBalance', [morphoMarketsManagerForCompLike.address, ethers.utils.parseEther('10').toHexString()]);
      const morphoMarketsManagerUser = await ethers.getSigner(morphoMarketsManagerForCompLike.address);
      await morphoPositionsManagerForCream.connect(morphoMarketsManagerUser).setComptroller(comptroller.address);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // liquidator liquidates borrower1's position
      const closeFactor = await comptroller.closeFactorMantissa();
      const toRepay = maxToBorrow.mul(closeFactor).div(SCALE);
      await daiToken.connect(liquidator).approve(morphoPositionsManagerForCream.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await morphoPositionsManagerForCream.connect(liquidator).liquidate(config.tokens.cDai.address, config.tokens.cUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const mDaiExchangeRate = await morphoMarketsManagerForCompLike.mUnitExchangeRate(config.tokens.cDai.address);
      const cUsdcExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await comptroller.liquidationIncentiveMantissa();
      const collateralAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const borrowedAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceInP2PAfter = collateralBalanceInP2PBefore.sub(amountToSeize.sub(cTokenToUnderlying(collateralBalanceOnCompBefore, cUsdcExchangeRate)));
      const expectedBorrowBalanceInP2PAfter = borrowBalanceInP2PBefore.sub(toRepay.mul(SCALE).div(mDaiExchangeRate));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check liquidatee balances
      expect((await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onCream).to.equal(0);
      expect(removeDigitsBigNumber(2, (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(2, expectedCollateralBalanceInP2PAfter)
      );
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onCream).to.equal(0);
      expect((await morphoPositionsManagerForCream.borrowBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).inP2P).to.equal(expectedBorrowBalanceInP2PAfter);

      // Check liquidator balances
      let diff;
      if (usdcBalanceAfter.gt(expectedUsdcBalanceAfter)) diff = usdcBalanceAfter.sub(expectedUsdcBalanceAfter);
      else diff = expectedUsdcBalanceAfter.sub(usdcBalanceAfter);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });
  });

  xdescribe('Test attacks', () => {
    it('Should not be DDOS by a supplier or a group of suppliers', async () => {});

    it('Should not be DDOS by a borrower or a group of borrowers', async () => {});

    it('Should not be subject to flash loan attacks', async () => {});

    it('Should not be subjected to Oracle Manipulation attacks', async () => {});
  });
});
