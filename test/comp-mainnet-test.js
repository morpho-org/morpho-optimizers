require('dotenv').config({ path: '.env.local' });
const { utils, BigNumber } = require('ethers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const hre = require('hardhat');
const config = require('@config/ethereum-config.json').mainnet;
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

describe('CompPositionsManager Contract', () => {
  let cUsdcToken;
  let cDaiToken;
  let cUsdtToken;
  let cMkrToken;
  let daiToken;
  let usdtToken;
  let uniToken;
  let CompPositionsManager;
  let compPositionsManager;
  let fakeCompoundModule;

  let signers;
  let owner;
  let lender1;
  let lender2;
  let lender3;
  let borrower1;
  let borrower2;
  let borrower3;
  let liquidator;
  let addrs;
  let lenders;
  let borrowers;

  let underlyingThreshold;

  beforeEach(async () => {
    // Users
    signers = await ethers.getSigners();
    [owner, lender1, lender2, lender3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
    lenders = [lender1, lender2, lender3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy contracts
    CompMarketsManager = await ethers.getContractFactory('CompMarketsManager');
    compMarketsManager = await CompMarketsManager.deploy(config.compound.comptroller.address);
    await compMarketsManager.deployed();

    CompPositionsManager = await ethers.getContractFactory('CompPositionsManager');
    compPositionsManager = await CompPositionsManager.deploy(compMarketsManager.address, config.compound.comptroller.address);
    fakeCompoundModule = await CompPositionsManager.deploy(compMarketsManager.address, config.compound.comptroller.address);
    await compPositionsManager.deployed();
    await fakeCompoundModule.deployed();

    // Get contract dependencies
    const cTokenAbi = require(config.tokens.cToken.abi);
    cUsdcToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdc.address, owner);
    cDaiToken = await ethers.getContractAt(cTokenAbi, config.tokens.cDai.address, owner);
    cUsdtToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdt.address, owner);
    cUniToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUni.address, owner);
    cMkrToken = await ethers.getContractAt(cTokenAbi, config.tokens.cMkr.address, owner);
    usdtToken = await ethers.getContractAt(require(config.tokens.usdt.abi), config.tokens.usdt.address, owner);
    comptroller = await ethers.getContractAt(require(config.compound.comptroller.abi), config.compound.comptroller.address, owner);
    compoundOracle = await ethers.getContractAt(require(config.compound.oracle.abi), comptroller.oracle(), owner);

    // Mint some ERC20
    daiToken = await getTokens('0x9759A6Ac90977b93B58547b4A71c78317f391A28', 'minter', signers, config.tokens.dai, utils.parseUnits('10000'));
    usdcToken = await getTokens('0x5b6122c109b78c6755486966148c1d70a50a47d7', 'minter', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    usdtToken = await getTokens('0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503', 'whale', signers, config.tokens.usdt, BigNumber.from(10).pow(10));
    uniToken = await getTokens('0x1a9c8182c09f50c8318d769245bea52c32be35bc', 'whale', signers, config.tokens.uni, utils.parseUnits('10000'));

    underlyingThreshold = utils.parseUnits('1');

    // Create and list markets
    await compMarketsManager.connect(owner).setCompPositionsManager(compPositionsManager.address);
    await compMarketsManager.connect(owner).createMarkets([config.tokens.cDai.address, config.tokens.cUsdc.address, config.tokens.cUsdt.address, config.tokens.cUni.address]);
    await compMarketsManager.connect(owner).listMarket(config.tokens.cDai.address);
    await compMarketsManager.connect(owner).updateThreshold(config.tokens.cUsdc.address, 0, BigNumber.from(1).pow(6));
    await compMarketsManager.connect(owner).listMarket(config.tokens.cUsdc.address);
    await compMarketsManager.connect(owner).updateThreshold(config.tokens.cUsdt.address, 0, BigNumber.from(1).pow(6));
    await compMarketsManager.connect(owner).listMarket(config.tokens.cUsdt.address);
    await compMarketsManager.connect(owner).listMarket(config.tokens.cUni.address);
  });

  describe('Deployment', () => {
    it('Should deploy the contract with the right values', async () => {
      // Calculate BPY
      const borrowRatePerBlock = await cDaiToken.borrowRatePerBlock();
      const supplyRatePerBlock = await cDaiToken.supplyRatePerBlock();
      const expectedBPY = borrowRatePerBlock.add(supplyRatePerBlock).div(2);
      expect(await compMarketsManager.BPY(config.tokens.cDai.address)).to.equal(expectedBPY);
      expect(await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address)).to.be.equal(utils.parseUnits('1'));

      // Thresholds
      underlyingThreshold = await compMarketsManager.thresholds(config.tokens.cDai.address, 0);
      expect(underlyingThreshold).to.be.equal(utils.parseUnits('1'));
      expect(await compMarketsManager.thresholds(config.tokens.cDai.address, 1)).to.be.equal(BigNumber.from(10).pow(5));
      expect(await compMarketsManager.thresholds(config.tokens.cDai.address, 2)).to.be.equal(BigNumber.from(10).pow(5));
    });
  });

  describe('Governance functions', () => {
    it('Should revert when at least one of the markets in input is not a real market', async () => {
      expect(compMarketsManager.connect(owner).createMarkets([config.tokens.usdt.address])).to.be.reverted;
      expect(compMarketsManager.connect(owner).createMarkets([config.tokens.cEth.address, config.tokens.usdt.address, config.tokens.cUni.address])).to.be.reverted;
      expect(compMarketsManager.connect(owner).createMarkets([config.tokens.cEth.address])).not.be.reverted;
    });

    it('Only Owner should be able to create markets on Morpho', async () => {
      expect(compMarketsManager.connect(lender1).createMarkets([config.tokens.cEth.address])).to.be.reverted;
      expect(compMarketsManager.connect(borrower1).createMarkets([config.tokens.cEth.address])).to.be.reverted;
      expect(compMarketsManager.connect(owner).createMarkets([config.tokens.cEth.address])).not.be.reverted;
    });

    it('Only Morpho should be able to create markets on CompPositionsManager', async () => {
      expect(compPositionsManager.connect(lender1).enterMarkets([config.tokens.cEth.address])).to.be.reverted;
      expect(compPositionsManager.connect(borrower1).enterMarkets([config.tokens.cEth.address])).to.be.reverted;
      expect(compPositionsManager.connect(owner).enterMarkets([config.tokens.cEth.address])).to.be.reverted;
      await compMarketsManager.connect(owner).createMarkets([config.tokens.cEth.address]);
      expect(await comptroller.checkMembership(compPositionsManager.address, config.tokens.cEth.address)).to.be.true;
    });

    it('Only Owner should be able to set compPositionsManager on Morpho', async () => {
      expect(compMarketsManager.connect(lender1).setCompPositionsManager(fakeCompoundModule.address)).to.be.reverted;
      expect(compMarketsManager.connect(borrower1).setCompPositionsManager(fakeCompoundModule.address)).to.be.reverted;
      expect(compMarketsManager.connect(owner).setCompPositionsManager(fakeCompoundModule.address)).not.be.reverted;
      await compMarketsManager.connect(owner).setCompPositionsManager(fakeCompoundModule.address);
      expect(await compMarketsManager.compPositionsManager()).to.equal(fakeCompoundModule.address);
    });

    it('Only Owner should be able to update thresholds', async () => {
      const newThreshold = utils.parseUnits('2');
      await compMarketsManager.connect(owner).updateThreshold(config.tokens.cUsdc.address, 0, newThreshold);
      await compMarketsManager.connect(owner).updateThreshold(config.tokens.cUsdc.address, 1, newThreshold);
      await compMarketsManager.connect(owner).updateThreshold(config.tokens.cUsdc.address, 2, newThreshold);
      await compMarketsManager.connect(owner).updateThreshold(config.tokens.cUsdc.address, 3, newThreshold);

      // Other accounts than Owner
      await expect(compMarketsManager.connect(lender1).updateThreshold(config.tokens.cUsdc.address, 2, newThreshold)).to.be.reverted;
      await expect(compMarketsManager.connect(borrower1).updateThreshold(config.tokens.cUsdc.address, 2, newThreshold)).to.be.reverted;
    });

    it('Only Owner should be allowed to list/unlisted a market', async () => {
      await compMarketsManager.connect(owner).createMarkets([config.tokens.cEth.address]);
      expect(compMarketsManager.connect(lender1).listMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(compMarketsManager.connect(borrower1).listMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(compMarketsManager.connect(lender1).unlistMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(compMarketsManager.connect(borrower1).unlistMarket(config.tokens.cEth.address)).to.be.reverted;
      expect(compMarketsManager.connect(owner).listMarket(config.tokens.cEth.address)).not.to.be.reverted;
      expect(compMarketsManager.connect(owner).unlistMarket(config.tokens.cEth.address)).not.to.be.reverted;
    });

    it('Should create a market the with right values', async () => {
      const lendBPY = await cMkrToken.supplyRatePerBlock();
      const borrowBPY = await cMkrToken.borrowRatePerBlock();
      const { blockNumber } = await compMarketsManager.connect(owner).createMarkets([config.tokens.cMkr.address]);
      expect(await compMarketsManager.isListed(config.tokens.cMkr.address)).not.to.be.true;

      const BPY = lendBPY.add(borrowBPY).div(2);
      expect(await compMarketsManager.BPY(config.tokens.cMkr.address)).to.equal(BPY);

      expect(await compMarketsManager.mUnitExchangeRate(config.tokens.cMkr.address)).to.equal(SCALE);
      expect(await compMarketsManager.lastUpdateBlockNumber(config.tokens.cMkr.address)).to.equal(blockNumber);
    });
  });

  describe('Lenders on Compound (no borrowers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp).to.equal(0);
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho).to.equal(0);
    });

    it('Should revert when lending less than the required threshold', async () => {
      await expect(compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, underlyingThreshold.sub(1))).to.be.reverted;
    });

    it('Should have the correct balances after lending', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(lender1).approve(compPositionsManager.address, amount);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, amount);
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
      expect(await cDaiToken.balanceOf(compPositionsManager.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho).to.equal(0);
    });

    it('Should be able to redeem ERC20 right after lending up to max lending balance', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      await daiToken.connect(lender1).approve(compPositionsManager.address, amount);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, amount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));

      const lendingBalanceOnComp = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw1 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate1);

      // TODO: improve this test to prevent attacks
      await expect(compPositionsManager.connect(lender1).redeem(toWithdraw1.add(utils.parseUnits('0.001')).toString())).to.be.reverted;

      // Update exchange rate
      await cDaiToken.connect(lender1).exchangeRateCurrent();
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw2 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate2);
      await compPositionsManager.connect(lender1).redeem(config.tokens.cDai.address, toWithdraw2);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());
      // Check ERC20 balance
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1.sub(amount).add(toWithdraw2));

      // Check cToken left are only dust in lending balance
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp).to.be.lt(1000);
      await expect(compPositionsManager.connect(lender1).redeem(config.tokens.cDai.address, utils.parseUnits('0.001'))).to.be.reverted;
    });

    it('Should be able to deposit more ERC20 after already having deposit ERC20', async () => {
      const amount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('10').mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());

      await daiToken.connect(lender1).approve(compPositionsManager.address, amountToApprove);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, amount);
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, amount);
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check lending balance
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect(await cDaiToken.balanceOf(compPositionsManager.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
    });

    it('Several lenders should be able to deposit and have the correct balances', async () => {
      const amount = utils.parseUnits('10');
      let expectedCTokenBalance = BigNumber.from(0);

      for (const i in lenders) {
        const lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(lender).approve(compPositionsManager.address, amount);
        await compPositionsManager.connect(lender).deposit(config.tokens.cDai.address, amount);
        const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
        expectedCTokenBalance = expectedCTokenBalance.add(expectedLendingBalanceOnComp);
        expect(removeDigitsBigNumber(7, await cDaiToken.balanceOf(compPositionsManager.address))).to.equal(removeDigitsBigNumber(7, expectedCTokenBalance));
        expect(removeDigitsBigNumber(4, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender.getAddress())).onComp)).to.equal(
          removeDigitsBigNumber(4, expectedLendingBalanceOnComp)
        );
        expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender.getAddress())).onMorpho).to.equal(0);
      }
    });
  });

  describe('Borrowers on Compound (no lenders)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho).to.equal(0);
    });

    it('Should revert when providing 0 as collateral', async () => {
      await expect(compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, 0)).to.be.reverted;
    });

    it('Should revert when borrowing less than threshold', async () => {
      const amount = to6Decimals(utils.parseUnits('10'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, amount);
      await expect(compPositionsManager.connect(lender1).borrow(config.tokens.cDai.address, amount)).to.be.reverted;
    });

    it('Should be able to borrow on Compound after providing collateral up to max', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, amount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, amount);
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInCToken = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp;
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const borrowIndex = await cDaiToken.borrowIndex();
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      const borrowingBalanceOnCompInUnderlying = cDUnitToUnderlying((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp, borrowIndex);
      let diff;
      if (borrowingBalanceOnCompInUnderlying.gt(maxToBorrow)) diff = borrowingBalanceOnCompInUnderlying.sub(maxToBorrow);
      else diff = maxToBorrow.sub(borrowingBalanceOnCompInUnderlying);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);

      // Check Morpho balances
      expect(await daiToken.balanceOf(compPositionsManager.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compPositionsManager.address)).to.equal(maxToBorrow);
    });

    it('Should not be able to borrow more than max allowed given an amount of collateral', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, amount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, amount);
      const collateralBalanceInCToken = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const moreThanMaxToBorrow = maxToBorrow.add(utils.parseUnits('0.0001'));

      // TODO: fix dust issue
      // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
      await expect(compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, moreThanMaxToBorrow)).to.be.reverted;
    });

    it('Several borrowers should be able to borrow and have the correct balances', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('10'));
      const borrowedAmount = utils.parseUnits('2');
      let expectedMorphoBorrowingBalance = BigNumber.from(0);
      let previousBorrowIndex = await cDaiToken.borrowIndex();

      for (const i in borrowers) {
        const borrower = borrowers[i];
        await usdcToken.connect(borrower).approve(compPositionsManager.address, collateralAmount);
        await compPositionsManager.connect(borrower).deposit(config.tokens.cUsdc.address, collateralAmount);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await compPositionsManager.connect(borrower).borrow(config.tokens.cDai.address, borrowedAmount);
        // We have one block delay from Compound
        const borrowIndex = await cDaiToken.borrowIndex();
        expectedMorphoBorrowingBalance = expectedMorphoBorrowingBalance.mul(borrowIndex).div(previousBorrowIndex).add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        const borrowingBalanceOnCompInUnderlying = cDUnitToUnderlying((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower.getAddress())).onComp, borrowIndex);
        let diff;
        if (borrowingBalanceOnCompInUnderlying.gt(borrowedAmount)) diff = borrowingBalanceOnCompInUnderlying.sub(borrowedAmount);
        else diff = borrowedAmount.sub(borrowingBalanceOnCompInUnderlying);
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        // Update previous borrow index
        previousBorrowIndex = borrowIndex;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(compPositionsManager.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compPositionsManager.address)).to.equal(expectedMorphoBorrowingBalance);
    });

    it('Borrower should be able to repay less than what is on Compound', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, amount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, amount);
      const collateralBalanceInCToken = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);

      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const borrowingBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp;
      const borrowIndex1 = await cDaiToken.borrowIndex();
      const borrowingBalanceOnCompInUnderlying = cDUnitToUnderlying(borrowingBalanceOnComp, borrowIndex1);
      const toRepay = borrowingBalanceOnCompInUnderlying.div(2);
      await daiToken.connect(borrower1).approve(compPositionsManager.address, toRepay);
      const borrowIndex2 = await cDaiToken.borrowIndex();
      await compPositionsManager.connect(borrower1).repay(config.tokens.cDai.address, toRepay);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      const expectedBalanceOnComp = borrowingBalanceOnComp.sub(underlyingToCdUnit(borrowingBalanceOnCompInUnderlying.div(2), borrowIndex2));
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(expectedBalanceOnComp);
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow).sub(toRepay));
    });
  });

  describe('P2P interactions between lender and borrowers', () => {
    it('Lender should withdraw her liquidity while not enough cToken on Morpho contract', async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(lendingAmount);
      await daiToken.connect(lender1).approve(compPositionsManager.address, lendingAmount);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, lendingAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp1 = underlyingToCToken(lendingAmount, cExchangeRate1);
      expect(await cDaiToken.balanceOf(compPositionsManager.address)).to.equal(expectedLendingBalanceOnComp1);
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp1);

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, collateralAmount);

      // Borrowers borrows lender1 amount
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, lendingAmount);

      // Check lender1 balances
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const mExchangeRate1 = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const expectedLendingBalanceOnComp2 = expectedLendingBalanceOnComp1.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await compMarketsManager.connect(owner).updateMUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate2 = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await compMarketsManager.BPY(config.tokens.cDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(compPositionsManager.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.gt(cTokenContractBalanceInUnderlying);

      // Expected borrowing balances
      const expectedMorphoBorrowingBalance = remainingToWithdraw.add(cTokenContractBalanceInUnderlying).sub(lendingBalanceOnCompInUnderlying);

      // Withdraw
      await compPositionsManager.connect(lender1).redeem(config.tokens.cDai.address, amountToWithdraw);
      const borrowIndex = await cDaiToken.borrowIndex();
      const expectedBorrowerBorrowingBalanceOnComp = underlyingToCdUnit(expectedMorphoBorrowingBalance, borrowIndex);
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(compPositionsManager.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      // Check borrow balance of Morphof
      expect(removeDigitsBigNumber(6, borrowBalance)).to.equal(removeDigitsBigNumber(6, expectedMorphoBorrowingBalance));

      // Check lender1 underlying balance
      expect(removeDigitsBigNumber(1, daiBalanceAfter2)).to.equal(removeDigitsBigNumber(1, expectedDaiBalanceAfter2));

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(4, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho)).to.equal(0);

      // Check borrowing balances of borrower1
      expect(removeDigitsBigNumber(6, (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp)).to.equal(
        removeDigitsBigNumber(6, expectedBorrowerBorrowingBalanceOnComp)
      );
      expect(removeDigitsBigNumber(4, (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho)).to.equal(0);
    });

    it('Lender should redeem her liquidity while enough cDaiToken on Morpho contract', async () => {
      const lendingAmount = utils.parseUnits('10');
      let lender;

      for (const i in lenders) {
        lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(lendingAmount);
        await daiToken.connect(lender).approve(compPositionsManager.address, lendingAmount);
        await compPositionsManager.connect(lender).deposit(config.tokens.cDai.address, lendingAmount);
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
        const expectedLendingBalanceOnComp = underlyingToCToken(lendingAmount, cExchangeRate);
        expect(removeDigitsBigNumber(4, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender.getAddress())).onComp)).to.equal(
          removeDigitsBigNumber(4, expectedLendingBalanceOnComp)
        );
      }

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, collateralAmount);

      // We pick lender2 because lender2 is inserted before lender3 with the current sorting mechanism
      const previousLender2LendingBalanceOnComp = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender2.getAddress())).onComp;

      // Borrowers borrows lender1 amount
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, lendingAmount);

      // Check lender2 balances
      const mExchangeRate1 = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      // Expected balances of lender2
      const expectedLendingBalanceOnComp2 = previousLender2LendingBalanceOnComp.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender2.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender2.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await compMarketsManager.connect(owner).updateMUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate2 = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await compMarketsManager.BPY(config.tokens.cDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(compPositionsManager.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.lt(cTokenContractBalanceInUnderlying);

      // lender3 balances before the withdraw
      const lender3LendingBalanceOnComp = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender3.getAddress())).onComp;
      const lender3LendingBalanceOnMorpho = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender3.getAddress())).onMorpho;

      // lender2 balances before the withdraw
      const lender2LendingBalanceOnComp = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender2.getAddress())).onComp;
      const lender2LendingBalanceOnMorpho = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender2.getAddress())).onMorpho;

      // borrower1 balances before the withdraw
      const borrower1BorrowingBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp;
      const borrower1BorrowingBalanceOnMorpho = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho;

      // Withdraw
      await compPositionsManager.connect(lender1).redeem(config.tokens.cDai.address, amountToWithdraw);
      const cExchangeRate4 = await cDaiToken.callStatic.exchangeRateStored();
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(compPositionsManager.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      const lender2LendingBalanceOnCompInUnderlying = cTokenToUnderlying(lender2LendingBalanceOnComp, cExchangeRate4);
      const amountToMove = bigNumberMin(lender2LendingBalanceOnCompInUnderlying, remainingToWithdraw);
      const mExchangeRate4 = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const expectedLender2LendingBalanceOnComp = lender2LendingBalanceOnComp.sub(underlyingToCToken(amountToMove, cExchangeRate4));
      const expectedLender2LendingBalanceOnMorpho = lender2LendingBalanceOnMorpho.add(underlyingToMUnit(amountToMove, mExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check lender1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(5, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho)).to.equal(0);

      // Check lending balances of lender2: lender2 should have replaced lender1
      expect(removeDigitsBigNumber(1, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender2.getAddress())).onComp)).to.equal(
        removeDigitsBigNumber(1, expectedLender2LendingBalanceOnComp)
      );
      expect(removeDigitsBigNumber(6, (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender2.getAddress())).onMorpho)).to.equal(
        removeDigitsBigNumber(6, expectedLender2LendingBalanceOnMorpho)
      );

      // Check lending balances of lender3: lender3 balances should not move
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender3.getAddress())).onComp).to.equal(lender3LendingBalanceOnComp);
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender3.getAddress())).onMorpho).to.equal(lender3LendingBalanceOnMorpho);

      // Check borrowing balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(borrower1BorrowingBalanceOnComp);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho).to.equal(borrower1BorrowingBalanceOnMorpho);
    });

    it('Borrower on Morpho only, should be able to repay all borrowing amount', async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits('10');
      await daiToken.connect(lender1).approve(compPositionsManager.address, lendingAmount);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, lendingAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = lendingAmount.div(2);

      await usdcToken.connect(borrower1).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, collateralAmount);
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, toBorrow);

      const borrowerBalanceOnMorpho = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho;
      const BPY = await compMarketsManager.BPY(config.tokens.cDai.address);
      await compMarketsManager.updateMUnitExchangeRate(config.tokens.cDai.address);
      const mUnitExchangeRate = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      // WARNING: Should be one block but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, BPY, 1, 0).toString();
      const toRepay = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(compPositionsManager.address);

      // Repay
      await daiToken.connect(borrower1).approve(compPositionsManager.address, toRepay);
      await compPositionsManager.connect(borrower1).repay(config.tokens.cDai.address, toRepay);
      const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(toRepay, cExchangeRate));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(0);
      // Commented here due to the pow function issue
      // expect(removeDigitsBigNumber(1, (await compPositionsManager.borrowingBalanceInOf(borrower1.getAddress())).onMorpho)).to.equal(0);

      // Check Morpho balances
      expect(await cDaiToken.balanceOf(compPositionsManager.address)).to.equal(expectedMorphoCTokenBalance);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compPositionsManager.address)).to.equal(0);
    });

    it('Borrower on Morpho and on Compound, should be able to repay all borrowing amount', async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('100000000');
      await daiToken.connect(lender1).approve(compPositionsManager.address, lendingAmount);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, lendingAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = lendingAmount.mul(2);
      const lendingBalanceOnComp = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, toBorrow);

      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoBorrowingBalance1 = toBorrow.sub(cTokenToUnderlying(lendingBalanceOnComp, cExchangeRate1));
      const morphoBorrowingBalanceBefore1 = await cDaiToken.callStatic.borrowBalanceCurrent(compPositionsManager.address);
      expect(removeDigitsBigNumber(3, morphoBorrowingBalanceBefore1)).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowingBalance1));
      await daiToken.connect(borrower1).approve(compPositionsManager.address, amountToApprove);

      const borrowerBalanceOnMorpho = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho;
      const BPY = await compMarketsManager.BPY(config.tokens.cDai.address);
      const mUnitExchangeRate = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      // WARNING: Should be 2 blocks but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, BPY, 1, 0).toString();
      const borrowerBalanceOnMorphoInUnderlying = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);

      // Compute how much to repay
      const doUpdate = await cDaiToken.borrowBalanceCurrent(compPositionsManager.address);
      await doUpdate.wait(1);
      const borrowIndex1 = await cDaiToken.borrowIndex();
      const borrowerBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp;
      const toRepay = borrowerBalanceOnComp.mul(borrowIndex1).div(SCALE).add(borrowerBalanceOnMorphoInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(compPositionsManager.address);

      // Repay
      await daiToken.connect(borrower1).approve(compPositionsManager.address, toRepay);
      const borrowIndex3 = await cDaiToken.callStatic.borrowIndex();
      await compPositionsManager.connect(borrower1).repay(config.tokens.cDai.address, toRepay);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(borrowerBalanceOnMorphoInUnderlying, cExchangeRate2));
      const expectedBalanceOnComp = borrowerBalanceOnComp.sub(borrowerBalanceOnComp.mul(borrowIndex1).div(borrowIndex3));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowingBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp;
      expect(removeDigitsBigNumber(2, borrower1BorrowingBalanceOnComp)).to.equal(removeDigitsBigNumber(2, expectedBalanceOnComp));
      // WARNING: Commented here due to the pow function issue
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho).to.be.lt(1000000000000);

      // Check Morpho balances
      expect(removeDigitsBigNumber(5, await cDaiToken.balanceOf(compPositionsManager.address))).to.equal(removeDigitsBigNumber(5, expectedMorphoCTokenBalance));
      // Issue here: we cannot access the most updated borrowing balance as it's updated during the repayBorrow on Compound.
      // const expectedMorphoBorrowingBalance2 = morphoBorrowingBalanceBefore2.sub(borrowerBalanceOnComp.mul(borrowIndex2).div(SCALE));
      // expect(removeDigitsBigNumber(3, await cToken.callStatic.borrowBalanceStored(compPositionsManager.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowingBalance2));
    });

    it('Should disconnect lender from Morpho when borrowing an asset that nobody has on compMarketsManager and the lending balance is partly used', async () => {
      // lender1 deposits DAI
      const lendingAmount = utils.parseUnits('100');
      await daiToken.connect(lender1).approve(compPositionsManager.address, lendingAmount);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, lendingAmount);

      // borrower1 deposits USDC as collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, collateralAmount);

      // borrower1 borrows part of the lending amount of lender1
      const amountToBorrow = lendingAmount.div(2);
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, amountToBorrow);
      const borrowingBalanceOnMorpho = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho;

      // lender1 borrows USDT that nobody is lending on Morpho
      const cDaiExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const mDaiExchangeRate1 = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const lendingBalanceOnComp1 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho1 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho;
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp1, cDaiExchangeRate1);
      const lendingBalanceMorphoInUnderlying = mUnitToUnderlying(lendingBalanceOnMorpho1, mDaiExchangeRate1);
      const lendingBalanceInUnderlying = lendingBalanceOnCompInUnderlying.add(lendingBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdtPriceMantissa = await compoundOracle.callStatic.getUnderlyingPrice(config.tokens.cUsdt.address);
      const daiPriceMantissa = await compoundOracle.callStatic.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = lendingBalanceInUnderlying.mul(daiPriceMantissa).div(usdtPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      await compPositionsManager.connect(lender1).borrow(config.tokens.cUsdt.address, maxToBorrow);

      // Check balances
      const lendingBalanceOnComp2 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      const borrowingBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp;
      const cDaiExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const cDaiBorrowIndex = await cDaiToken.borrowIndex();
      const mDaiExchangeRate2 = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const expectedBorrowingBalanceOnComp = mUnitToUnderlying(borrowingBalanceOnMorpho, mDaiExchangeRate2).mul(SCALE).div(cDaiBorrowIndex);
      const usdtBorrowingBalance = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cUsdt.address, lender1.getAddress())).onComp;
      const cUsdtBorrowIndex = await cUsdtToken.borrowIndex();
      const usdtBorrowingBalanceInUnderlying = usdtBorrowingBalance.mul(cUsdtBorrowIndex).div(SCALE);
      expect(removeDigitsBigNumber(5, lendingBalanceOnComp2)).to.equal(removeDigitsBigNumber(5, underlyingToCToken(lendingBalanceInUnderlying, cDaiExchangeRate2)));
      expect(removeDigitsBigNumber(2, borrowingBalanceOnComp)).to.equal(removeDigitsBigNumber(2, expectedBorrowingBalanceOnComp));
      expect(removeDigitsBigNumber(1, usdtBorrowingBalanceInUnderlying)).to.equal(removeDigitsBigNumber(1, maxToBorrow));
    });

    it('Lender should be connected to borrowers already on Morpho when depositing', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const lendingAmount = utils.parseUnits('100');
      const borrowingAmount = utils.parseUnits('30');

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, collateralAmount);
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, borrowingAmount);
      const borrower1BorrowingBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp;

      // borrower2 borrows
      await usdcToken.connect(borrower2).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower2).deposit(config.tokens.cUsdc.address, collateralAmount);
      await compPositionsManager.connect(borrower2).borrow(config.tokens.cDai.address, borrowingAmount);
      const borrower2BorrowingBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower2.getAddress())).onComp;

      // borrower3 borrows
      await usdcToken.connect(borrower3).approve(compPositionsManager.address, collateralAmount);
      await compPositionsManager.connect(borrower3).deposit(config.tokens.cUsdc.address, collateralAmount);
      await compPositionsManager.connect(borrower3).borrow(config.tokens.cDai.address, borrowingAmount);
      const borrower3BorrowingBalanceOnComp = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower3.getAddress())).onComp;

      // lender1 deposit
      await daiToken.connect(lender1).approve(compPositionsManager.address, lendingAmount);
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, lendingAmount);
      const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
      const borrowIndex = await cDaiToken.borrowIndex();
      const mUnitExchangeRate = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);

      // Check balances
      const lendingBalanceOnMorpho = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onMorpho;
      const lendingBalanceOnComp = (await compPositionsManager.lendingBalanceInOf(config.tokens.cDai.address, lender1.getAddress())).onComp;
      const underlyingMatched = cDUnitToUnderlying(borrower1BorrowingBalanceOnComp.add(borrower2BorrowingBalanceOnComp).add(borrower3BorrowingBalanceOnComp), borrowIndex);
      expectedLendingBalanceOnMorpho = underlyingMatched.mul(SCALE).div(mUnitExchangeRate);
      expectedLendingBalanceOnComp = underlyingToCToken(lendingAmount.sub(underlyingMatched), cExchangeRate);
      expect(removeDigitsBigNumber(2, lendingBalanceOnMorpho)).to.equal(removeDigitsBigNumber(2, expectedLendingBalanceOnMorpho));
      expect(lendingBalanceOnComp).to.equal(expectedLendingBalanceOnComp);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.be.lte(1);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower2.getAddress())).onComp).to.be.lte(1);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower3.getAddress())).onComp).to.be.lte(1);
    });
  });

  describe('Test liquidation', () => {
    it('Borrower should be liquidated while lending (collateral) is only on Compound', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, amount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, amount);
      const collateralBalanceInCToken = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);

      // Borrow
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const collateralBalanceBefore = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp;
      const borrowingBalanceBefore = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp;

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate
      const toRepay = maxToBorrow.div(2);
      await daiToken.connect(liquidator).approve(compPositionsManager.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await compPositionsManager.connect(liquidator).liquidate(config.tokens.cDai.address, config.tokens.cUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const borrowIndex = await cDaiToken.borrowIndex();
      const cUsdcExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await comptroller.liquidationIncentiveMantissa();
      const collateralAssetPrice = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const borrowedAssetPrice = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceAfter = collateralBalanceBefore.sub(underlyingToCToken(amountToSeize, cUsdcExchangeRate));
      const expectedBorrowingBalanceAfter = borrowingBalanceBefore.sub(underlyingToCdUnit(toRepay, borrowIndex));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check balances
      expect(removeDigitsBigNumber(6, (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp)).to.equal(
        removeDigitsBigNumber(6, expectedCollateralBalanceAfter)
      );
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(expectedBorrowingBalanceAfter);
      expect(removeDigitsBigNumber(1, usdcBalanceAfter)).to.equal(removeDigitsBigNumber(1, expectedUsdcBalanceAfter));
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });

    it('Borrower should be liquidated while lending (collateral) is on Compound and on Morpho', async () => {
      await daiToken.connect(lender1).approve(compPositionsManager.address, utils.parseUnits('1000'));
      await compPositionsManager.connect(lender1).deposit(config.tokens.cDai.address, utils.parseUnits('1000'));

      // borrower1 deposits USDC as lending (collateral)
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compPositionsManager.address, amount);
      await compPositionsManager.connect(borrower1).deposit(config.tokens.cUsdc.address, amount);

      // borrower2 borrows part of lending of borrower1 -> borrower1 has lending on Morpho and on Compound
      const toBorrow = amount;
      await uniToken.connect(borrower2).approve(compPositionsManager.address, utils.parseUnits('200'));
      await compPositionsManager.connect(borrower2).deposit(config.tokens.cUni.address, utils.parseUnits('200'));
      await compPositionsManager.connect(borrower2).borrow(config.tokens.cUsdc.address, toBorrow);

      // borrower1 borrows DAI
      const cUsdcExchangeRate1 = await cUsdcToken.callStatic.exchangeRateCurrent();
      const mUsdcExchangeRate1 = await compMarketsManager.mUnitExchangeRate(config.tokens.cUsdc.address);
      const lendingBalanceOnComp1 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp;
      const lendingBalanceOnMorpho1 = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onMorpho;
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp1, cUsdcExchangeRate1);
      const lendingBalanceMorphoInUnderlying = mUnitToUnderlying(lendingBalanceOnMorpho1, mUsdcExchangeRate1);
      const lendingBalanceInUnderlying = lendingBalanceOnCompInUnderlying.add(lendingBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const maxToBorrow = lendingBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      await compPositionsManager.connect(borrower1).borrow(config.tokens.cDai.address, maxToBorrow);
      const collateralBalanceOnCompBefore = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp;
      const collateralBalanceOnMorphoBefore = (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onMorpho;
      const borrowingBalanceOnMorphoBefore = (await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho;

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // liquidator liquidates borrower1's position
      const closeFactor = await comptroller.closeFactorMantissa();
      const toRepay = maxToBorrow.mul(closeFactor).div(SCALE);
      await daiToken.connect(liquidator).approve(compPositionsManager.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await compPositionsManager.connect(liquidator).liquidate(config.tokens.cDai.address, config.tokens.cUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const mDaiExchangeRate = await compMarketsManager.mUnitExchangeRate(config.tokens.cDai.address);
      const cUsdcExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await comptroller.liquidationIncentiveMantissa();
      const collateralAssetPrice = await compoundOracle.getUnderlyingPrice(config.tokens.cUsdc.address);
      const borrowedAssetPrice = await compoundOracle.getUnderlyingPrice(config.tokens.cDai.address);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceOnMorphoAfter = collateralBalanceOnMorphoBefore.sub(amountToSeize.sub(cTokenToUnderlying(collateralBalanceOnCompBefore, cUsdcExchangeRate)));
      const expectedBorrowingBalanceOnMorphoAfter = borrowingBalanceOnMorphoBefore.sub(toRepay.mul(SCALE).div(mDaiExchangeRate));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check liquidatee balances
      expect((await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onComp).to.equal(0);
      expect(removeDigitsBigNumber(2, (await compPositionsManager.lendingBalanceInOf(config.tokens.cUsdc.address, borrower1.getAddress())).onMorpho)).to.equal(
        removeDigitsBigNumber(2, expectedCollateralBalanceOnMorphoAfter)
      );
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compPositionsManager.borrowingBalanceInOf(config.tokens.cDai.address, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorphoAfter);

      // Check liquidator balances
      let diff;
      if (usdcBalanceAfter.gt(expectedUsdcBalanceAfter)) diff = usdcBalanceAfter.sub(expectedUsdcBalanceAfter);
      else diff = expectedUsdcBalanceAfter.sub(usdcBalanceAfter);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });
  });

  xdescribe('Test attacks', () => {
    it('Should not be DDOS by a lender or a group of lenders', async () => {});

    it('Should not be DDOS by a borrower or a group of borrowers', async () => {});

    it('Should not be subject to flash loan attacks', async () => {});

    it('Should not be subjected to Oracle Manipulation attacks', async () => {});
  });
});
