require('dotenv').config({ path: '.env.local' });
const { utils, BigNumber } = require('ethers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const hre = require('hardhat');
const config = require('@config/polygon/config.json').polygon;
const { removeDigitsBigNumber, bigNumberMin, to6Decimals, getTokens } = require('./utils/common-helpers');
const {
  RAY,
  SCALE,
  underlyingToScaledBalance,
  scaledBalanceToUnderlying,
  underlyingToMUnit,
  mUnitToUnderlying,
  underlyingToAdUnit,
  aDUnitToUnderlying,
  computeNewMorphoExchangeRate,
  computeNewBorrowIndex,
} = require('./utils/aave-helpers');

describe('MorphoPositionsManagerForAave Contract', () => {
  const SECOND_PER_YEAR = BigNumber.from(31536000);
  const PERCENT_BASE = BigNumber.from(10000);

  let aUsdcToken;
  let aDaiToken;
  let aUsdtToken;
  let aWbtcToken;
  let daiToken;
  let usdtToken;
  let wbtToken;
  let MorphoPositionsManagerForAave;
  let morphoPositionsManagerForAave;
  let morphoMarketsManagerForAave;
  let fakeAavePositionsManager;
  let lendingPool;
  let lendingPoolAddressesProvider;
  let protocolDataProvider;

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

  beforeEach(async () => {
    // Users
    signers = await ethers.getSigners();
    [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
    suppliers = [supplier1, supplier2, supplier3];
    borrowers = [borrower1, borrower2, borrower3];

    const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
    const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
    await redBlackBinaryTree.deployed();

    // Deploy contracts
    const MorphoMarketsManagerForAave = await ethers.getContractFactory('MorphoMarketsManagerForAave');
    morphoMarketsManagerForAave = await MorphoMarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
    await morphoMarketsManagerForAave.deployed();

    MorphoPositionsManagerForAave = await ethers.getContractFactory('MorphoPositionsManagerForAave', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    morphoPositionsManagerForAave = await MorphoPositionsManagerForAave.deploy(morphoMarketsManagerForAave.address, config.aave.lendingPoolAddressesProvider.address);
    fakeAavePositionsManager = await MorphoPositionsManagerForAave.deploy(morphoMarketsManagerForAave.address, config.aave.lendingPoolAddressesProvider.address);
    await morphoPositionsManagerForAave.deployed();
    await fakeAavePositionsManager.deployed();

    // Get contract dependencies
    const aTokenAbi = require(config.tokens.aToken.abi);
    const stableDebtTokenAbi = require(config.tokens.stableDebtToken.abi);
    aUsdcToken = await ethers.getContractAt(aTokenAbi, config.tokens.aUsdc.address, owner);
    stableDebtUsdcToken = await ethers.getContractAt(stableDebtTokenAbi, config.tokens.stableDebtUsdc.address, owner);
    aDaiToken = await ethers.getContractAt(aTokenAbi, config.tokens.aDai.address, owner);
    stableDebtDaiToken = await ethers.getContractAt(stableDebtTokenAbi, config.tokens.stableDebtDai.address, owner);
    aUsdtToken = await ethers.getContractAt(aTokenAbi, config.tokens.aUsdt.address, owner);
    stableDebtUsdtToken = await ethers.getContractAt(stableDebtTokenAbi, config.tokens.stableDebtUsdt.address, owner);
    aWbtcToken = await ethers.getContractAt(aTokenAbi, config.tokens.aWbtc.address, owner);
    stableDebtWbtcToken = await ethers.getContractAt(stableDebtTokenAbi, config.tokens.stableDebtWbtc.address, owner);

    lendingPool = await ethers.getContractAt(require(config.aave.lendingPool.abi), config.aave.lendingPool.address, owner);
    lendingPoolAddressesProvider = await ethers.getContractAt(require(config.aave.lendingPoolAddressesProvider.abi), config.aave.lendingPoolAddressesProvider.address, owner);
    protocolDataProvider = await ethers.getContractAt(
      require(config.aave.protocolDataProvider.abi),
      lendingPoolAddressesProvider.getAddress('0x1000000000000000000000000000000000000000000000000000000000000000'),
      owner
    );
    oracle = await ethers.getContractAt(require(config.aave.oracle.abi), lendingPoolAddressesProvider.getPriceOracle(), owner);

    // Mint some ERC20
    daiToken = await getTokens('0x27f8d03b3a2196956ed754badc28d73be8830a6e', 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
    usdcToken = await getTokens('0x1a13f4ca1d028320a707d99520abfefca3998b7f', 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    usdtToken = await getTokens('0x44aaa9ebafb4557605de574d5e968589dc3a84d1', 'whale', signers, config.tokens.usdt, BigNumber.from(10).pow(10));
    wbtToken = await getTokens('0xdc9232e2df177d7a12fdff6ecbab114e2231198d', 'whale', signers, config.tokens.wbtc, BigNumber.from(10).pow(8));
    wmatiaToken = await getTokens('0xadbf1854e5883eb8aa7baf50705338739e558e5b', 'whale', signers, config.tokens.wmatic, utils.parseUnits('100'));

    underlyingThreshold = utils.parseUnits('1');

    // Create and list markets
    await morphoMarketsManagerForAave.connect(owner).setPositionsManagerForAave(morphoPositionsManagerForAave.address);
    await morphoMarketsManagerForAave.connect(owner).setLendingPool();
    await morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address);
    await morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address);
    await morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address);
    await morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address);
    await morphoMarketsManagerForAave.connect(owner).updateThreshold(config.tokens.aUsdc.address, BigNumber.from(1).pow(6));
    await morphoMarketsManagerForAave.connect(owner).updateThreshold(config.tokens.aUsdt.address, BigNumber.from(1).pow(6));
  });

  describe('Deployment', () => {
    it('Should deploy the contract with the right values', async () => {
      // Calculate p2pBPY
      const reserveData = await lendingPool.getReserveData(config.tokens.dai.address);
      const currentLiquidityRate = reserveData.currentLiquidityRate;
      const currentVariableBorrowRate = reserveData.currentVariableBorrowRate;
      const expectedBPY = currentLiquidityRate.add(currentVariableBorrowRate).div(2).div(SECOND_PER_YEAR);
      expect(await morphoMarketsManagerForAave.p2pBPY(config.tokens.aDai.address)).to.equal(expectedBPY);
      expect(await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address)).to.be.equal(RAY);

      // Thresholds
      underlyingThreshold = await morphoPositionsManagerForAave.thresholds(config.tokens.aDai.address);
      expect(underlyingThreshold).to.be.equal(utils.parseUnits('1'));
    });
  });

  describe('Governance functions', () => {
    it('Should revert when at least when a market in input is not a real market', async () => {
      expect(morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.usdt.address)).to.be.reverted;
    });

    it('Only Owner should be able to create markets in peer-to-peer', async () => {
      expect(morphoMarketsManagerForAave.connect(supplier1).createMarket(config.tokens.aWeth.address)).to.be.reverted;
      expect(morphoMarketsManagerForAave.connect(borrower1).createMarket(config.tokens.aWeth.address)).to.be.reverted;
      expect(morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.aWeth.address)).not.be.reverted;
    });

    it('Only Morpho should be able to create markets on MorphoPositionsManagerForAave', async () => {
      expect(morphoMarketsManagerForAave.connect(supplier1).createMarket(config.tokens.aWeth.address)).to.be.reverted;
      expect(morphoMarketsManagerForAave.connect(borrower1).createMarket(config.tokens.aWeth.address)).to.be.reverted;
      await morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.aWeth.address);
    });

    it('marketsManagerForAave should not be changed after already set by Owner', async () => {
      expect(morphoMarketsManagerForAave.connect(owner).setPositionsManagerForAave(fakeAavePositionsManager.address)).to.be.reverted;
    });

    it('Only Owner should be able to update thresholds', async () => {
      const newThreshold = utils.parseUnits('2');
      await morphoMarketsManagerForAave.connect(owner).updateThreshold(config.tokens.aUsdc.address, newThreshold);

      // Other accounts than Owner
      await expect(morphoMarketsManagerForAave.connect(supplier1).updateThreshold(config.tokens.aUsdc.address, newThreshold)).to.be.reverted;
      await expect(morphoMarketsManagerForAave.connect(borrower1).updateThreshold(config.tokens.aUsdc.address, newThreshold)).to.be.reverted;
    });

    it('Should create a market the with right values', async () => {
      const reserveData = await lendingPool.getReserveData(config.tokens.wmatic.address);
      const currentLiquidityRate = reserveData.currentLiquidityRate;
      const currentVariableBorrowRate = reserveData.currentVariableBorrowRate;
      console.log(currentLiquidityRate.toString());
      console.log(currentVariableBorrowRate.toString());
      const expectedBPY = currentLiquidityRate.add(currentVariableBorrowRate).div(2).div(SECOND_PER_YEAR);
      await morphoMarketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address);
      expect(await morphoMarketsManagerForAave.isCreated(config.tokens.aWmatic.address)).to.be.true;
      expect(await morphoMarketsManagerForAave.p2pBPY(config.tokens.aWmatic.address)).to.equal(expectedBPY);
      expect(await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aWmatic.address)).to.equal(RAY);
    });
  });

  describe('Suppliers on Aave (no borrowers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave).to.equal(0);
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should revert when supply less than the required threshold', async () => {
      await expect(morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, underlyingThreshold.sub(1))).to.be.reverted;
    });

    it('Should have the correct balances after supply', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, amount);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedSupplyBalanceOnAave = underlyingToScaledBalance(amount, normalizedIncome);
      expect(await aDaiToken.balanceOf(morphoPositionsManagerForAave.address)).to.equal(amount);
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave)).to.equal(
        removeDigitsBigNumber(1, expectedSupplyBalanceOnAave)
      );
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should be able to withdraw ERC20 right after supply up to max supply balance', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, amount);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));

      const supplyBalanceOnAave = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const toWithdraw1 = scaledBalanceToUnderlying(supplyBalanceOnAave, normalizedIncome1);

      // TODO: improve this test to prevent attacks
      await expect(morphoPositionsManagerForAave.connect(supplier1).withdraw(toWithdraw1.add(utils.parseUnits('0.001')).toString())).to.be.reverted;

      // Here we must calculate the next normalized income
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const toWithdraw2 = scaledBalanceToUnderlying(supplyBalanceOnAave, normalizedIncome2);
      await morphoPositionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, toWithdraw2);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());
      // Check ERC20 balance
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1.sub(amount).add(toWithdraw2));

      // Check aToken left are only dust in supply balance
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave).to.be.lt(BigNumber.from(10).pow(12));
      await expect(morphoPositionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, utils.parseUnits('0.001'))).to.be.reverted;
    });

    it('Should be able to supply more ERC20 after already having supply ERC20', async () => {
      const amount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('10').mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());

      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, amountToApprove);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check supply balance
      const expectedSupplyBalanceOnAave1 = underlyingToScaledBalance(amount, normalizedIncome1);
      const expectedSupplyBalanceOnAave2 = underlyingToScaledBalance(amount, normalizedIncome2);
      const expectedSupplyBalanceOnAave = expectedSupplyBalanceOnAave1.add(expectedSupplyBalanceOnAave2);
      expect(removeDigitsBigNumber(2, await aDaiToken.scaledBalanceOf(morphoPositionsManagerForAave.address))).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceOnAave));
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave)).to.equal(
        removeDigitsBigNumber(1, expectedSupplyBalanceOnAave)
      );
    });

    it('Several suppliers should be able to supply and have the correct balances', async () => {
      const amount = utils.parseUnits('10');
      let expectedScaledBalance = BigNumber.from(0);

      for (const i in suppliers) {
        const supplier = suppliers[i];
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(supplier).approve(morphoPositionsManagerForAave.address, amount);
        await morphoPositionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, amount);
        const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());
        const expectedSupplyBalanceOnAave = underlyingToScaledBalance(amount, normalizedIncome);

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        expectedScaledBalance = expectedScaledBalance.add(expectedSupplyBalanceOnAave);
        let diff;
        const scaledBalance = await aDaiToken.scaledBalanceOf(morphoPositionsManagerForAave.address);
        if (scaledBalance.gt(expectedScaledBalance)) diff = scaledBalance.sub(expectedScaledBalance);
        else diff = expectedScaledBalance.sub(scaledBalance);
        expect(removeDigitsBigNumber(2, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).onAave)).to.equal(
          removeDigitsBigNumber(2, expectedSupplyBalanceOnAave)
        );
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).inP2P).to.equal(0);
      }
    });
  });

  describe('Borrowers on Aave (no suppliers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.equal(0);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(0);
    });

    it('Should revert when providing 0 as collateral', async () => {
      await expect(morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, 0)).to.be.reverted;
    });

    it('Should revert when borrow less than threshold', async () => {
      const amount = to6Decimals(utils.parseUnits('10'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, amount);
      await expect(morphoPositionsManagerForAave.connect(supplier1).borrow(config.tokens.aDai.address, amount)).to.be.reverted;
    });

    it('Should be able to borrow on Aave after providing collateral up to max', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, amount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave;
      const collateralBalanceInUnderlying = scaledBalanceToUnderlying(collateralBalanceInScaledBalance, normalizedIncome);
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(config.tokens.dai.address);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.usdc.address);
      const usdcDecimals = await usdcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(config.tokens.dai.address);
      const daiDecimals = await daiToken.decimals();
      const maxToBorrow = collateralBalanceInUnderlying
        .mul(usdcPrice)
        .div(BigNumber.from(10).pow(usdcDecimals))
        .mul(BigNumber.from(10).pow(daiDecimals))
        .div(daiPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);

      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      const borrowBalanceOnAaveInUnderlying = aDUnitToUnderlying(
        (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave,
        normalizedVariableDebt
      );
      let diff;
      if (borrowBalanceOnAaveInUnderlying.gt(maxToBorrow)) diff = borrowBalanceOnAaveInUnderlying.sub(underlyingToAdUnit(maxToBorrow, normalizedVariableDebt));
      else diff = maxToBorrow.sub(borrowBalanceOnAaveInUnderlying);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);
      // Check Morpho balances
      expect(await daiToken.balanceOf(morphoPositionsManagerForAave.address)).to.equal(0);
      expect(await stableDebtDaiToken.balanceOf(morphoPositionsManagerForAave.address)).to.equal(maxToBorrow);
    });

    it('Should not be able to borrow more than max allowed given an amount of collateral', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, amount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave;
      const collateralBalanceInUnderlying = scaledBalanceToUnderlying(collateralBalanceInScaledBalance, normalizedIncome);
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(config.tokens.dai.address);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.usdc.address);
      const usdcDecimals = await usdcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(config.tokens.dai.address);
      const daiDecimals = await daiToken.decimals();
      const maxToBorrow = collateralBalanceInUnderlying
        .mul(usdcPrice)
        .div(BigNumber.from(10).pow(usdcDecimals))
        .mul(BigNumber.from(10).pow(daiDecimals))
        .div(daiPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);
      // WARNING: maxToBorrow seems to be not accurate
      const moreThanMaxToBorrow = maxToBorrow.add(utils.parseUnits('10'));

      // TODO: fix dust issue
      // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
      await expect(morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, moreThanMaxToBorrow)).to.be.reverted;
    });

    it('Several borrowers should be able to borrow and have the correct balances', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('10'));
      const borrowedAmount = utils.parseUnits('2');
      let expectedMorphoBorrowBalance = BigNumber.from(0);
      let previousNormalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);

      for (const i in borrowers) {
        const borrower = borrowers[i];
        await usdcToken.connect(borrower).approve(morphoPositionsManagerForAave.address, collateralAmount);
        await morphoPositionsManagerForAave.connect(borrower).supply(config.tokens.aUsdc.address, collateralAmount);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await morphoPositionsManagerForAave.connect(borrower).borrow(config.tokens.aDai.address, borrowedAmount);
        // We have one block delay from Aave
        const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
        expectedMorphoBorrowBalance = expectedMorphoBorrowBalance.mul(normalizedVariableDebt).div(previousNormalizedVariableDebt).add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        const borrowBalanceOnAaveInUnderlying = aDUnitToUnderlying(
          (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower.getAddress())).onAave,
          normalizedVariableDebt
        );
        let diff;
        if (borrowBalanceOnAaveInUnderlying.gt(borrowedAmount)) diff = borrowBalanceOnAaveInUnderlying.sub(borrowedAmount);
        else diff = borrowedAmount.sub(borrowBalanceOnAaveInUnderlying);
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        // Update previous borrow index
        previousNormalizedVariableDebt = normalizedVariableDebt;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(morphoPositionsManagerForAave.address)).to.equal(0);
      expect(removeDigitsBigNumber(2, await stableDebtDaiToken.balanceOf(morphoPositionsManagerForAave.address))).to.equal(removeDigitsBigNumber(2, expectedMorphoBorrowBalance));
    });

    it('Borrower should be able to repay less than what is on Aave', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, amount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave;
      const collateralBalanceInUnderlying = scaledBalanceToUnderlying(collateralBalanceInScaledBalance, normalizedIncome);
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(config.tokens.dai.address);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.usdc.address);
      const usdcDecimals = await usdcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(config.tokens.dai.address);
      const daiDecimals = await daiToken.decimals();
      const maxToBorrow = collateralBalanceInUnderlying
        .mul(usdcPrice)
        .div(BigNumber.from(10).pow(usdcDecimals))
        .mul(BigNumber.from(10).pow(daiDecimals))
        .div(daiPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);

      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const borrowBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave;
      const normalizeVariableDebt1 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const borrowBalanceOnAaveInUnderlying = aDUnitToUnderlying(borrowBalanceOnAave, normalizeVariableDebt1);
      const toRepay = borrowBalanceOnAaveInUnderlying.div(2);
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, toRepay);
      await morphoPositionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const normalizeVariableDebt2 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      const expectedBalanceOnAave = borrowBalanceOnAave.sub(underlyingToAdUnit(borrowBalanceOnAaveInUnderlying.div(2), normalizeVariableDebt2));
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave)).to.equal(
        removeDigitsBigNumber(1, expectedBalanceOnAave)
      );
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow).sub(toRepay));
    });
  });

  describe('P2P interactions between supplier and borrowers', () => {
    it('Supplier should withdraw her liquidity while not enough aToken in peer-to-peer contract', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(supplyAmount);
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, supplyAmount);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedSupplyBalanceOnAave1 = underlyingToScaledBalance(supplyAmount, cExchangeRate1);
      expect(await aDaiToken.balanceOf(morphoPositionsManagerForAave.address)).to.equal(expectedSupplyBalanceOnAave1);
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave).to.equal(expectedSupplyBalanceOnAave1);

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);

      // Borrowers borrows supplier1 amount
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, supplyAmount);

      // Check supplier1 balances
      const cExchangeRate2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const mExchangeRate1 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const expectedSupplyBalanceOnAave2 = expectedSupplyBalanceOnAave1.sub(underlyingToScaledBalance(supplyAmount, cExchangeRate2));
      const expectedSupplyBalanceInP2P2 = underlyingToMUnit(supplyAmount, mExchangeRate1);
      const supplyBalanceOnAave2 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const supplyBalanceInP2P2 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      expect(supplyBalanceOnAave2).to.equal(expectedSupplyBalanceOnAave2);
      expect(supplyBalanceInP2P2).to.equal(expectedSupplyBalanceInP2P2);

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.equal(0);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(expectedBorrowBalanceInP2P1);

      // Compare remaining to withdraw and the aToken contract balance
      await morphoMarketsManagerForAave.connect(owner).updateMUnitExchangeRate(config.tokens.aDai.address);
      const mExchangeRate2 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morphoMarketsManagerForAave.p2pBPY(config.tokens.aDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnAave3 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const supplyBalanceInP2P3 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      const cExchangeRate3 = await aDaiToken.callStatic.exchangeRateStored();
      const supplyBalanceOnAaveInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnAave3, cExchangeRate3);
      const amountToWithdraw = supplyBalanceOnAaveInUnderlying.add(mUnitToUnderlying(supplyBalanceInP2P3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnAaveInUnderlying);
      const aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(await aDaiToken.balanceOf(morphoPositionsManagerForAave.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.gt(aTokenContractBalanceInUnderlying);

      // Expected borrow balances
      const expectedMorphoBorrowBalance = remainingToWithdraw.add(aTokenContractBalanceInUnderlying).sub(supplyBalanceOnAaveInUnderlying);

      // Withdraw
      await morphoPositionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, amountToWithdraw);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const expectedBorrowerBorrowBalanceOnAave = underlyingToAdUnit(expectedMorphoBorrowBalance, normalizedVariableDebt);
      const borrowBalance = await aDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForAave.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      // Check borrow balance of Morpho
      expect(removeDigitsBigNumber(10, borrowBalance)).to.equal(removeDigitsBigNumber(10, expectedMorphoBorrowBalance));

      // Check supplier1 underlying balance
      expect(removeDigitsBigNumber(1, daiBalanceAfter2)).to.equal(removeDigitsBigNumber(1, expectedDaiBalanceAfter2));

      // Check supply balances of supplier1
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave)).to.equal(0);
      expect(removeDigitsBigNumber(9, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P)).to.equal(0);

      // Check borrow balances of borrower1
      expect(removeDigitsBigNumber(9, (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave)).to.equal(
        removeDigitsBigNumber(9, expectedBorrowerBorrowBalanceOnAave)
      );
      expect(removeDigitsBigNumber(9, (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P)).to.equal(0);
    });

    it('Supplier should withdraw her liquidity while enough aDaiToken in peer-to-peer contract', async () => {
      const supplyAmount = utils.parseUnits('10');
      let supplier;

      for (const i in suppliers) {
        supplier = suppliers[i];
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(supplyAmount);
        await daiToken.connect(supplier).approve(morphoPositionsManagerForAave.address, supplyAmount);
        await morphoPositionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, supplyAmount);
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const normalizedIncome = await aDaiToken.callStatic.exchangeRateStored();
        const expectedSupplyBalanceOnAave = underlyingToScaledBalance(supplyAmount, normalizedIncome);
        expect(removeDigitsBigNumber(4, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).onAave)).to.equal(
          removeDigitsBigNumber(4, expectedSupplyBalanceOnAave)
        );
      }

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);

      const previousSupplier1SupplyBalanceOnAave = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;

      // Borrowers borrows supplier1 amount
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, supplyAmount);

      // Check supplier1 balances
      const mExchangeRate1 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const cExchangeRate2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      // Expected balances of supplier1
      const expectedSupplyBalanceOnAave2 = previousSupplier1SupplyBalanceOnAave.sub(underlyingToScaledBalance(supplyAmount, cExchangeRate2));
      const expectedSupplyBalanceInP2P2 = underlyingToMUnit(supplyAmount, mExchangeRate1);
      const supplyBalanceOnAave2 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const supplyBalanceInP2P2 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      expect(supplyBalanceOnAave2).to.equal(expectedSupplyBalanceOnAave2);
      expect(supplyBalanceInP2P2).to.equal(expectedSupplyBalanceInP2P2);

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.equal(0);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(expectedBorrowBalanceInP2P1);

      // Compare remaining to withdraw and the aToken contract balance
      await morphoMarketsManagerForAave.connect(owner).updateMUnitExchangeRate(config.tokens.aDai.address);
      const mExchangeRate2 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morphoMarketsManagerForAave.p2pBPY(config.tokens.aDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnAave3 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const supplyBalanceInP2P3 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      const cExchangeRate3 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const supplyBalanceOnAaveInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnAave3, cExchangeRate3);
      const amountToWithdraw = supplyBalanceOnAaveInUnderlying.add(mUnitToUnderlying(supplyBalanceInP2P3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnAaveInUnderlying);
      const aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(await aDaiToken.balanceOf(morphoPositionsManagerForAave.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.lt(aTokenContractBalanceInUnderlying);

      // supplier3 balances before the withdraw
      const supplier3SupplyBalanceOnAave = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).onAave;
      const supplier3SupplyBalanceInP2P = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).inP2P;

      // supplier2 balances before the withdraw
      const supplier2SupplyBalanceOnAave = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).onAave;
      const supplier2SupplyBalanceInP2P = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).inP2P;

      // borrower1 balances before the withdraw
      const borrower1BorrowBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave;
      const borrower1BorrowBalanceInP2P = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;

      // Withdraw
      await morphoPositionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, amountToWithdraw);
      const cExchangeRate4 = await aDaiToken.callStatic.exchangeRateStored();
      const borrowBalance = await aDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForAave.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      const supplier2SupplyBalanceOnAaveInUnderlying = scaledBalanceToUnderlying(supplier2SupplyBalanceOnAave, cExchangeRate4);
      const amountToMove = bigNumberMin(supplier2SupplyBalanceOnAaveInUnderlying, remainingToWithdraw);
      const mExchangeRate4 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const expectedSupplier2SupplyBalanceOnAave = supplier2SupplyBalanceOnAave.sub(underlyingToScaledBalance(amountToMove, cExchangeRate4));
      const expectedSupplier2SupplyBalanceInP2P = supplier2SupplyBalanceInP2P.add(underlyingToMUnit(amountToMove, mExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check supplier1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check supply balances of supplier1
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave)).to.equal(0);
      expect(removeDigitsBigNumber(5, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P)).to.equal(0);

      // Check supply balances of supplier2: supplier2 should have replaced supplier1
      expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).onAave)).to.equal(
        removeDigitsBigNumber(1, expectedSupplier2SupplyBalanceOnAave)
      );
      expect(removeDigitsBigNumber(7, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(7, expectedSupplier2SupplyBalanceInP2P)
      );

      // Check supply balances of supplier3: supplier3 balances should not move
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).onAave).to.equal(supplier3SupplyBalanceOnAave);
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).inP2P).to.equal(supplier3SupplyBalanceInP2P);

      // Check borrow balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.equal(borrower1BorrowBalanceOnAave);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(borrower1BorrowBalanceInP2P);
    });

    it('Borrower in peer-to-peer only, should be able to repay all borrow amount', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, supplyAmount);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.div(2);

      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow);

      const borrowerBalanceInP2P = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;
      const p2pBPY = await morphoMarketsManagerForAave.p2pBPY(config.tokens.aDai.address);
      await morphoMarketsManagerForAave.updateMUnitExchangeRate(config.tokens.aDai.address);
      const mUnitExchangeRate = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      // WARNING: Should be one block but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, p2pBPY, 1, 0).toString();
      const toRepay = mUnitToUnderlying(borrowerBalanceInP2P, mExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await aDaiToken.balanceOf(morphoPositionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, toRepay);
      await morphoPositionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const normalizedIncome = await aDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToScaledBalance(toRepay, normalizedIncome));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.equal(0);
      // Commented here due to the pow function issue
      // expect(removeDigitsBigNumber(1, (await morphoPositionsManagerForAave.borrowBalanceInOf(borrower1.getAddress())).inP2P)).to.equal(0);

      // Check Morpho balances
      expect(await aDaiToken.balanceOf(morphoPositionsManagerForAave.address)).to.equal(expectedMorphoCTokenBalance);
      expect(await aDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForAave.address)).to.equal(0);
    });

    it('Borrower in peer-to-peer and on Aave, should be able to repay all borrow amount', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('100000000');
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, supplyAmount);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.mul(2);
      const supplyBalanceOnAave = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow);

      const cExchangeRate1 = await aDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoBorrowBalance1 = toBorrow.sub(scaledBalanceToUnderlying(supplyBalanceOnAave, cExchangeRate1));
      const morphoBorrowBalanceBefore1 = await aDaiToken.callStatic.borrowBalanceCurrent(morphoPositionsManagerForAave.address);
      expect(removeDigitsBigNumber(6, morphoBorrowBalanceBefore1)).to.equal(removeDigitsBigNumber(6, expectedMorphoBorrowBalance1));
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, amountToApprove);

      const borrowerBalanceInP2P = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;
      const p2pBPY = await morphoMarketsManagerForAave.p2pBPY(config.tokens.aDai.address);
      const mUnitExchangeRate = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      // WARNING: Should be 2 blocks but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, p2pBPY, 1, 0).toString();
      const borrowerBalanceInP2PInUnderlying = mUnitToUnderlying(borrowerBalanceInP2P, mExchangeRate);

      // Compute how much to repay
      const doUpdate = await aDaiToken.borrowBalanceCurrent(morphoPositionsManagerForAave.address);
      await doUpdate.wait(1);
      const normalizeVariableDebt1 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const borrowerBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave;
      const toRepay = borrowerBalanceOnAave.mul(normalizeVariableDebt1).div(SCALE).add(borrowerBalanceInP2PInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await aDaiToken.balanceOf(morphoPositionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, toRepay);
      const normalizeVariableDebt3 = await aDaiToken.callStatic.normalizedVariableDebt();
      await morphoPositionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const cExchangeRate2 = await aDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToScaledBalance(borrowerBalanceInP2PInUnderlying, cExchangeRate2));
      const expectedBalanceOnAave = borrowerBalanceOnAave.sub(borrowerBalanceOnAave.mul(normalizeVariableDebt1).div(normalizeVariableDebt3));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave;
      expect(removeDigitsBigNumber(2, borrower1BorrowBalanceOnAave)).to.equal(removeDigitsBigNumber(2, expectedBalanceOnAave));
      // WARNING: Commented here due to the pow function issue
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.be.lt(1000000000000);

      // Check Morpho balances
      expect(removeDigitsBigNumber(5, await aDaiToken.balanceOf(morphoPositionsManagerForAave.address))).to.equal(removeDigitsBigNumber(5, expectedMorphoCTokenBalance));
      // Issue here: we cannot access the most updated borrow balance as it's updated during the repayBorrow on Aave.
      // const expectedMorphoBorrowBalance2 = morphoBorrowBalanceBefore2.sub(borrowerBalanceOnAave.mul(normalizeVariableDebt2).div(SCALE));
      // expect(removeDigitsBigNumber(3, await aToken.callStatic.borrowBalanceStored(morphoPositionsManagerForAave.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowBalance2));
    });

    it('Should disconnect supplier from Morpho when borrow an asset that nobody has on morphoMarketsManagerForAave and the supply balance is partly used', async () => {
      // supplier1 supplys DAI
      const supplyAmount = utils.parseUnits('100');
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, supplyAmount);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);

      // borrower1 supplys USDC as collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);

      // borrower1 borrows part of the supply amount of supplier1
      const amountToBorrow = supplyAmount.div(2);
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, amountToBorrow);
      const borrowBalanceInP2P = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;

      // supplier1 borrows USDT that nobody is supply in peer-to-peer
      const cDaiExchangeRate1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const mDaiExchangeRate1 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const supplyBalanceOnAave1 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const supplyBalanceInP2P1 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      const supplyBalanceOnAaveInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnAave1, cDaiExchangeRate1);
      const supplyBalanceMorphoInUnderlying = mUnitToUnderlying(supplyBalanceInP2P1, mDaiExchangeRate1);
      const supplyBalanceInUnderlying = supplyBalanceOnAaveInUnderlying.add(supplyBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await lendingPool.markets(config.tokens.aDai.address);
      const usdtPriceMantissa = await oracle.callStatic.getUnderlyingPrice(config.tokens.aUsdt.address);
      const daiPrice = await oracle.callStatic.getUnderlyingPrice(config.tokens.aDai.address);
      const maxToBorrow = supplyBalanceInUnderlying.mul(daiPrice).div(usdtPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      await morphoPositionsManagerForAave.connect(supplier1).borrow(config.tokens.aUsdt.address, maxToBorrow);

      // Check balances
      const supplyBalanceOnAave2 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const borrowBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave;
      const cDaiExchangeRate2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const cDaiBorrowIndex = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const mDaiExchangeRate2 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const expectedBorrowBalanceOnAave = mUnitToUnderlying(borrowBalanceInP2P, mDaiExchangeRate2).mul(SCALE).div(cDaiBorrowIndex);
      const usdtBorrowBalance = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aUsdt.address, supplier1.getAddress())).onAave;
      const cUsdtBorrowIndex = await aUsdtToken.normalizedVariableDebt();
      const usdtBorrowBalanceInUnderlying = usdtBorrowBalance.mul(cUsdtBorrowIndex).div(SCALE);
      expect(removeDigitsBigNumber(6, supplyBalanceOnAave2)).to.equal(removeDigitsBigNumber(6, underlyingToScaledBalance(supplyBalanceInUnderlying, cDaiExchangeRate2)));
      expect(removeDigitsBigNumber(2, borrowBalanceOnAave)).to.equal(removeDigitsBigNumber(2, expectedBorrowBalanceOnAave));
      expect(removeDigitsBigNumber(2, usdtBorrowBalanceInUnderlying)).to.equal(removeDigitsBigNumber(2, maxToBorrow));
    });

    it('Supplier should be connected to borrowers already in peer-to-peer when supplying', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const supplyAmount = utils.parseUnits('100');
      const borrowAmount = utils.parseUnits('30');

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, borrowAmount);
      const borrower1BorrowBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave;

      // borrower2 borrows
      await usdcToken.connect(borrower2).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower2).supply(config.tokens.aUsdc.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower2).borrow(config.tokens.aDai.address, borrowAmount);
      const borrower2BorrowBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower2.getAddress())).onAave;

      // borrower3 borrows
      await usdcToken.connect(borrower3).approve(morphoPositionsManagerForAave.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower3).supply(config.tokens.aUsdc.address, collateralAmount);
      await morphoPositionsManagerForAave.connect(borrower3).borrow(config.tokens.aDai.address, borrowAmount);
      const borrower3BorrowBalanceOnAave = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower3.getAddress())).onAave;

      // supplier1 supply
      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, supplyAmount);
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);
      const normalizedIncome = await aDaiToken.callStatic.exchangeRateStored();
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const mUnitExchangeRate = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);

      // Check balances
      const supplyBalanceInP2P = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      const supplyBalanceOnAave = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onAave;
      const underlyingMatched = aDUnitToUnderlying(borrower1BorrowBalanceOnAave.add(borrower2BorrowBalanceOnAave).add(borrower3BorrowBalanceOnAave), normalizedVariableDebt);
      expectedSupplyBalanceInP2P = underlyingMatched.mul(SCALE).div(mUnitExchangeRate);
      expectedSupplyBalanceOnAave = underlyingToScaledBalance(supplyAmount.sub(underlyingMatched), normalizedIncome);
      expect(removeDigitsBigNumber(2, supplyBalanceInP2P)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceInP2P));
      expect(supplyBalanceOnAave).to.equal(expectedSupplyBalanceOnAave);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.be.lte(1);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower2.getAddress())).onAave).to.be.lte(1);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower3.getAddress())).onAave).to.be.lte(1);
    });
  });

  describe('Test liquidation', () => {
    it('Borrower should be liquidated while supply (collateral) is only on Cream', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await lendingPool.admin();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      // Deposit
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, amount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const collateralBalanceInScaledBalance = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave;
      const normalizedIncome = await aUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = scaledBalanceToUnderlying(collateralBalanceInScaledBalance, normalizedIncome);
      const { collateralFactorMantissa } = await lendingPool.markets(config.tokens.aUsdc.address);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.aUsdc.address);
      const daiPrice = await oracle.getAssetPrice(config.tokens.aDai.address);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPrice).div(daiPrice).mul(collateralFactorMantissa).div(SCALE);

      // Borrow
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const collateralBalanceBefore = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave;
      const borrowBalanceBefore = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave;

      // Set price oracle
      await lendingPool.connect(admin)._setPriceOracle(priceOracle.address);
      priceOracle.setUnderlyingPrice(config.tokens.aDai.address, BigNumber.from('1010182920000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.aUsdc.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.aWbtc.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.aUsdt.address, BigNumber.from('1000000000000000000000000000000'));

      // Force oracle update by setting lendingPool again (but with the custom price oracle)
      await hre.network.provider.send('hardhat_impersonateAccount', [morphoMarketsManagerForAave.address]);
      await hre.network.provider.send('hardhat_setBalance', [morphoMarketsManagerForAave.address, ethers.utils.parseEther('10').toHexString()]);
      const morphoMarketsManagerUser = await ethers.getSigner(morphoMarketsManagerForAave.address);
      await morphoPositionsManagerForAave.connect(morphoMarketsManagerUser).setComptroller(lendingPool.address);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate
      const toRepay = maxToBorrow.div(2);
      await daiToken.connect(liquidator).approve(morphoPositionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await morphoPositionsManagerForAave.connect(liquidator).liquidate(config.tokens.aDai.address, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const cUsdcExchangeRate = await aUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await lendingPool.liquidationIncentiveMantissa();
      const collateralAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.aUsdc.address);
      const borrowedAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.aDai.address);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceAfter = collateralBalanceBefore.sub(underlyingToScaledBalance(amountToSeize, cUsdcExchangeRate));
      const expectedBorrowBalanceAfter = borrowBalanceBefore.sub(underlyingToAdUnit(toRepay, normalizedVariableDebt));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check balances
      expect(removeDigitsBigNumber(6, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave)).to.equal(
        removeDigitsBigNumber(6, expectedCollateralBalanceAfter)
      );
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.equal(expectedBorrowBalanceAfter);
      expect(removeDigitsBigNumber(1, usdcBalanceAfter)).to.equal(removeDigitsBigNumber(1, expectedUsdcBalanceAfter));
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });

    it('Borrower should be liquidated while supply (collateral) is on Aave and in peer-to-peer', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await lendingPool.admin();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      await daiToken.connect(supplier1).approve(morphoPositionsManagerForAave.address, utils.parseUnits('1000'));
      await morphoPositionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, utils.parseUnits('1000'));

      // borrower1 supplys USDC as supply (collateral)
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(morphoPositionsManagerForAave.address, amount);
      await morphoPositionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);

      // borrower2 borrows part of supply of borrower1 -> borrower1 has supply in peer-to-peer and on Cream
      const toBorrow = amount;
      await wbtToken.connect(borrower2).approve(morphoPositionsManagerForAave.address, utils.parseUnits('50'));
      await morphoPositionsManagerForAave.connect(borrower2).supply(config.tokens.aWbtc.address, utils.parseUnits('50'));
      await morphoPositionsManagerForAave.connect(borrower2).borrow(config.tokens.aUsdc.address, toBorrow);

      // borrower1 borrows DAI
      const cUsdcExchangeRate1 = await aUsdcToken.callStatic.exchangeRateCurrent();
      const mUsdcExchangeRate1 = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aUsdc.address);
      const supplyBalanceOnAave1 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave;
      const supplyBalanceInP2P1 = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P;
      const supplyBalanceOnAaveInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnAave1, cUsdcExchangeRate1);
      const supplyBalanceMorphoInUnderlying = mUnitToUnderlying(supplyBalanceInP2P1, mUsdcExchangeRate1);
      const supplyBalanceInUnderlying = supplyBalanceOnAaveInUnderlying.add(supplyBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await lendingPool.markets(config.tokens.aUsdc.address);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.aUsdc.address);
      const daiPrice = await oracle.getAssetPrice(config.tokens.aDai.address);
      const maxToBorrow = supplyBalanceInUnderlying.mul(usdcPrice).div(daiPrice).mul(collateralFactorMantissa).div(SCALE);
      await morphoPositionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const collateralBalanceOnAaveBefore = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave;
      const collateralBalanceInP2PBefore = (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P;
      const borrowBalanceInP2PBefore = (await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;

      // Set price oracle
      await lendingPool.connect(admin)._setPriceOracle(priceOracle.address);
      priceOracle.setUnderlyingPrice(config.tokens.aDai.address, BigNumber.from('1020182920000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.aUsdc.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.aWbtc.address, BigNumber.from('1000000000000000000000000000000'));
      priceOracle.setUnderlyingPrice(config.tokens.aUsdt.address, BigNumber.from('1000000000000000000000000000000'));

      // Force oracle update by setting lendingPool again (but with the custom price oracle)
      await hre.network.provider.send('hardhat_impersonateAccount', [morphoMarketsManagerForAave.address]);
      await hre.network.provider.send('hardhat_setBalance', [morphoMarketsManagerForAave.address, ethers.utils.parseEther('10').toHexString()]);
      const morphoMarketsManagerUser = await ethers.getSigner(morphoMarketsManagerForAave.address);
      await morphoPositionsManagerForAave.connect(morphoMarketsManagerUser).setComptroller(lendingPool.address);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // liquidator liquidates borrower1's position
      const closeFactor = await lendingPool.closeFactorMantissa();
      const toRepay = maxToBorrow.mul(closeFactor).div(SCALE);
      await daiToken.connect(liquidator).approve(morphoPositionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await morphoPositionsManagerForAave.connect(liquidator).liquidate(config.tokens.aDai.address, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const mDaiExchangeRate = await morphoMarketsManagerForAave.mUnitExchangeRate(config.tokens.aDai.address);
      const cUsdcExchangeRate = await aUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await lendingPool.liquidationIncentiveMantissa();
      const collateralAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.aUsdc.address);
      const borrowedAssetPrice = await priceOracle.getUnderlyingPrice(config.tokens.aDai.address);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceInP2PAfter = collateralBalanceInP2PBefore.sub(amountToSeize.sub(scaledBalanceToUnderlying(collateralBalanceOnAaveBefore, cUsdcExchangeRate)));
      const expectedBorrowBalanceInP2PAfter = borrowBalanceInP2PBefore.sub(toRepay.mul(SCALE).div(mDaiExchangeRate));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check liquidatee balances
      expect((await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onAave).to.equal(0);
      expect(removeDigitsBigNumber(2, (await morphoPositionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(2, expectedCollateralBalanceInP2PAfter)
      );
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onAave).to.equal(0);
      expect((await morphoPositionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(expectedBorrowBalanceInP2PAfter);

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
