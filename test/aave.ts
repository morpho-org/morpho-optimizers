import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { MAX_INT, removeDigitsBigNumber, bigNumberMin, to6Decimals, getTokens, roundBigNumber } from './utils/common-helpers';
import {
  WAD,
  RAY,
  underlyingToScaledBalance,
  scaledBalanceToUnderlying,
  underlyingToP2PUnit,
  p2pUnitToUnderlying,
  underlyingToAdUnit,
  aDUnitToUnderlying,
  computeNewMorphoExchangeRate,
} from './utils/aave-helpers';

describe('PositionsManagerForAave Contract', () => {
  const LIQUIDATION_CLOSE_FACTOR_PERCENT: BigNumber = BigNumber.from(5000);
  const SECOND_PER_YEAR: BigNumber = BigNumber.from(31536000);
  const PERCENT_BASE: BigNumber = BigNumber.from(10000);
  const AVERAGE_BLOCK_TIME: number = 2;

  // Tokens
  let aDaiToken: Contract;
  let daiToken: Contract;
  let usdcToken: Contract;
  let wbtcToken: Contract;
  let wmaticToken: Contract;
  let variableDebtDaiToken: Contract;

  // Contracts
  let positionsManagerForAave: Contract;
  let marketsManagerForAave: Contract;
  let fakeAavePositionsManager: Contract;
  let lendingPool: Contract;
  let lendingPoolAddressesProvider: Contract;
  let protocolDataProvider: Contract;
  let oracle: Contract;
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
  let attacker: Signer;

  let underlyingThreshold: BigNumber;
  let snapshotId: number;

  const initialize = async () => {
    // Signers
    signers = await ethers.getSigners();
    [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator, attacker] = signers;
    suppliers = [supplier1, supplier2, supplier3];
    borrowers = [borrower1, borrower2, borrower3];

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
    daiToken = await getTokens(config.tokens.dai.whale, 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
    usdcToken = await getTokens(config.tokens.usdc.whale, 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    wbtcToken = await getTokens(config.tokens.wbtc.whale, 'whale', signers, config.tokens.wbtc, BigNumber.from(10).pow(8));
    wmaticToken = await getTokens(config.tokens.wmatic.whale, 'whale', signers, config.tokens.wmatic, utils.parseUnits('100'));
    underlyingThreshold = WAD;

    // Create and list markets
    await marketsManagerForAave.connect(owner).setPositionsManager(positionsManagerForAave.address);
    await marketsManagerForAave.connect(owner).updateLendingPool();
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, WAD, MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address, BigNumber.from(10).pow(4), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address, WAD, MAX_INT);
  };

  before(initialize);

  beforeEach(async () => {
    snapshotId = await hre.network.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await hre.network.provider.send('evm_revert', [snapshotId]);
  });

  describe('Deployment', () => {
    it('Should deploy the contract with the right values', async () => {
      // Calculate p2pSPYs
      const reserveData = await lendingPool.getReserveData(config.tokens.dai.address);
      const currentLiquidityRate = reserveData.currentLiquidityRate;
      const currentVariableBorrowRate = reserveData.currentVariableBorrowRate;
      const expectedSPY = currentLiquidityRate.add(currentVariableBorrowRate).div(2).div(SECOND_PER_YEAR);
      expect(await marketsManagerForAave.supplyP2pSPY(config.tokens.aDai.address)).to.equal(expectedSPY);
      expect(await marketsManagerForAave.borrowP2pSPY(config.tokens.aDai.address)).to.equal(expectedSPY);
      expect(await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address)).to.be.equal(RAY);
      expect(await marketsManagerForAave.borrowP2pExchangeRate(config.tokens.aDai.address)).to.be.equal(RAY);

      // Thresholds
      underlyingThreshold = await positionsManagerForAave.threshold(config.tokens.aDai.address);
      expect(underlyingThreshold).to.be.equal(WAD);
    });
  });

  describe('Governance functions', () => {
    it('Should revert when at least when a market in input is not a real market', async () => {
      expect(marketsManagerForAave.connect(owner).createMarket(config.tokens.usdt.address, WAD)).to.be.reverted;
    });

    it('Only Owner should be able to create markets in peer-to-peer', async () => {
      expect(marketsManagerForAave.connect(supplier1).createMarket(config.tokens.aWeth.address, WAD, MAX_INT)).to.be.reverted;
      expect(marketsManagerForAave.connect(borrower1).createMarket(config.tokens.aWeth.address, WAD, MAX_INT)).to.be.reverted;
      expect(marketsManagerForAave.connect(owner).createMarket(config.tokens.aWeth.address, WAD, MAX_INT)).not.be.reverted;
    });

    it('marketsManagerForAave should not be changed after already set by Owner', async () => {
      expect(marketsManagerForAave.connect(owner).setPositionsManager(fakeAavePositionsManager.address)).to.be.reverted;
    });

    it('Only Owner should be able to update thresholds', async () => {
      const newCapValue = utils.parseUnits('2');
      await marketsManagerForAave.connect(owner).updateCapValue(config.tokens.aUsdc.address, newCapValue);
      expect(await positionsManagerForAave.capValue(config.tokens.aUsdc.address)).to.be.equal(newCapValue);

      // Other accounts than Owner
      await expect(marketsManagerForAave.connect(supplier1).updateCapValue(config.tokens.aUsdc.address, newCapValue)).to.be.reverted;
      await expect(marketsManagerForAave.connect(borrower1).updateCapValue(config.tokens.aUsdc.address, newCapValue)).to.be.reverted;
    });

    it('Should create a market the with right values', async () => {
      const reserveData = await lendingPool.getReserveData(config.tokens.aave.address);
      const currentLiquidityRate = reserveData.currentLiquidityRate;
      const currentVariableBorrowRate = reserveData.currentVariableBorrowRate;
      const expectedSPY = currentLiquidityRate.add(currentVariableBorrowRate).div(2).div(SECOND_PER_YEAR);
      await marketsManagerForAave.connect(owner).createMarket(config.tokens.aAave.address, WAD, MAX_INT);
      expect(await marketsManagerForAave.isCreated(config.tokens.aAave.address)).to.be.true;
      expect(await marketsManagerForAave.supplyP2pSPY(config.tokens.aAave.address)).to.equal(expectedSPY);
      expect(await marketsManagerForAave.borrowP2pSPY(config.tokens.aAave.address)).to.equal(expectedSPY);
      expect(await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aAave.address)).to.equal(RAY);
      expect(await marketsManagerForAave.borrowP2pExchangeRate(config.tokens.aAave.address)).to.equal(RAY);
    });

    it('Should update NMAX', async () => {
      const newNMAX = BigNumber.from(3000);
      expect(marketsManagerForAave.connect(supplier1).setNmaxForMatchingEngine(newNMAX)).to.be.reverted;
      expect(marketsManagerForAave.connect(borrower1).setNmaxForMatchingEngine(newNMAX)).to.be.reverted;
      expect(positionsManagerForAave.connect(owner).setNmaxForMatchingEngine(newNMAX)).to.be.reverted;
      await marketsManagerForAave.connect(owner).setNmaxForMatchingEngine(newNMAX);
      expect(await positionsManagerForAave.NMAX()).to.equal(newNMAX);
    });
  });

  describe('Suppliers on Aave (no borrowers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool).to.equal(0);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should revert when supply less than the required threshold', async () => {
      await expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, underlyingThreshold.sub(1), 0)).to.be
        .reverted;
    });

    it('Should have the correct balances after supply', async () => {
      const amount: BigNumber = utils.parseUnits('10');
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount, 0);
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedSupplyBalanceOnPool = underlyingToScaledBalance(amount, normalizedIncome);
      expect((await aDaiToken.balanceOf(positionsManagerForAave.address)).sub(amount)).to.be.lte(10);
      // expect(await aDaiToken.balanceOf(positionsManagerForAave.address)).to.equal(amount);
      expect(
        removeDigitsBigNumber(
          3,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool));
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should be able to withdraw ERC20 right after supply up to max supply balance', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount, 0);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));

      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .onPool;
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const toWithdraw1 = scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome1);

      // TODO: improve this test to prevent attacks
      await expect(positionsManagerForAave.connect(supplier1).withdraw(toWithdraw1.add(utils.parseUnits('0.001')).toString())).to.be
        .reverted;

      // Here we must calculate the next normalized income
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const toWithdraw2 = scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome2);
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, toWithdraw2);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());
      // Check ERC20 balance
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1.sub(amount).add(toWithdraw2));

      // Check aToken left are only dust in supply balance
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool).to.be.lt(
        BigNumber.from(10).pow(12)
      );
      await expect(positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, utils.parseUnits('0.001'))).to.be
        .reverted;
    });

    it('Should be able to withdraw all (on Pool only)', async () => {
      const amount = utils.parseUnits('20');
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount, 0);
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, MAX_INT);
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter).to.be.gt(daiBalanceBefore);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool).to.equal(0);
    });

    it('Should be able to supply more ERC20 after already having supply ERC20', async () => {
      const amount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('10').mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());

      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, amountToApprove);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount, 0);
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount, 0);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check supply balance
      const expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(amount, normalizedIncome1);
      const expectedSupplyBalanceOnPool2 = underlyingToScaledBalance(amount, normalizedIncome2);
      const expectedSupplyBalanceOnPool = expectedSupplyBalanceOnPool1.add(expectedSupplyBalanceOnPool2);
      expect(removeDigitsBigNumber(3, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(3, expectedSupplyBalanceOnPool)
      );
      expect(
        removeDigitsBigNumber(
          3,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool));
    });

    it('Several suppliers should be able to supply and have the correct balances', async () => {
      const amount = utils.parseUnits('10');
      let expectedScaledBalance = BigNumber.from(0);

      for (const supplier of suppliers) {
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(supplier).approve(positionsManagerForAave.address, amount);
        await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, amount, 0);
        const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());
        const expectedSupplyBalanceOnPool = underlyingToScaledBalance(amount, normalizedIncome);

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        expectedScaledBalance = expectedScaledBalance.add(expectedSupplyBalanceOnPool);
        let diff;
        const scaledBalance = await aDaiToken.scaledBalanceOf(positionsManagerForAave.address);
        if (scaledBalance.gt(expectedScaledBalance)) diff = scaledBalance.sub(expectedScaledBalance);
        else diff = expectedScaledBalance.sub(scaledBalance);
        expect(
          removeDigitsBigNumber(
            3,
            (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).onPool
          )
        ).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool));
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).inP2P).to.equal(0);
      }
    });
  });

  describe('Borrowers on Aave (no suppliers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(0);
    });

    it('Should revert when providing 0 as collateral', async () => {
      await expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, 0)).to.be.reverted;
    });

    it('Should revert when borrow less than threshold', async () => {
      const amount = to6Decimals(utils.parseUnits('10'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await expect(positionsManagerForAave.connect(supplier1).borrow(config.tokens.aDai.address, amount, 0)).to.be.reverted;
    });

    it('Should be able to borrow on Aave after providing collateral up to max', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).onPool;
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
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow, 0);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);

      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      const borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
        (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool,
        normalizedVariableDebt
      );
      let diff;
      if (borrowBalanceOnPoolInUnderlying.gt(maxToBorrow))
        diff = borrowBalanceOnPoolInUnderlying.sub(underlyingToAdUnit(maxToBorrow, normalizedVariableDebt));
      else diff = maxToBorrow.sub(borrowBalanceOnPoolInUnderlying);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);
      // Check Morpho balances
      expect(await daiToken.balanceOf(positionsManagerForAave.address)).to.equal(0);
      expect(removeDigitsBigNumber(2, await variableDebtDaiToken.balanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(2, maxToBorrow)
      );
    });

    it('Should not be able to borrow more than max allowed given an amount of collateral', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).onPool;
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
      await expect(positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, moreThanMaxToBorrow)).to.be.reverted;
    });

    it('Several borrowers should be able to borrow and have the correct balances', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('10'));
      const borrowedAmount = utils.parseUnits('2');
      let expectedMorphoBorrowBalance = BigNumber.from(0);
      let previousNormalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);

      for (const i in borrowers) {
        const borrower = borrowers[i];
        await usdcToken.connect(borrower).approve(positionsManagerForAave.address, collateralAmount);
        await positionsManagerForAave.connect(borrower).supply(config.tokens.aUsdc.address, collateralAmount, 0);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await positionsManagerForAave.connect(borrower).borrow(config.tokens.aDai.address, borrowedAmount, 0);
        // We have one block delay from Aave
        const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
        expectedMorphoBorrowBalance = expectedMorphoBorrowBalance
          .mul(normalizedVariableDebt)
          .div(previousNormalizedVariableDebt)
          .add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        const borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
          (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower.getAddress())).onPool,
          normalizedVariableDebt
        );
        let diff;
        if (borrowBalanceOnPoolInUnderlying.gt(borrowedAmount)) diff = borrowBalanceOnPoolInUnderlying.sub(borrowedAmount);
        else diff = borrowedAmount.sub(borrowBalanceOnPoolInUnderlying);
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        // Update previous borrow index
        previousNormalizedVariableDebt = normalizedVariableDebt;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(positionsManagerForAave.address)).to.equal(0);
      expect(removeDigitsBigNumber(3, await variableDebtDaiToken.balanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(3, expectedMorphoBorrowBalance)
      );
    });

    it('Borrower should be able to repay less than what is on Aave', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).onPool;
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
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow, 0);
      const borrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .onPool;
      const normalizeVariableDebt1 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(borrowBalanceOnPool, normalizeVariableDebt1);
      const toRepay = borrowBalanceOnPoolInUnderlying.div(2);
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);
      await positionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const normalizeVariableDebt2 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      const expectedBalanceOnPool = borrowBalanceOnPool.sub(
        underlyingToAdUnit(borrowBalanceOnPoolInUnderlying.div(2), normalizeVariableDebt2)
      );
      expect(
        removeDigitsBigNumber(
          2,
          (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(2, expectedBalanceOnPool));
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow).sub(toRepay));
    });

    it('Borrower should be able to repay all (on Pool only)', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      const toBorrow = utils.parseUnits('50');
      const hugeAmount = utils.parseUnits('100');
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow, 0);

      // Repay all
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, hugeAmount);
      await positionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, MAX_INT);
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
    });
  });

  describe('P2P interactions between supplier and borrowers', () => {
    it('Supplier should withdraw her liquidity while not enough aToken in peer-to-peer contract', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(supplyAmount);
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount, 0);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(supplyAmount, normalizedIncome1);
      expect(removeDigitsBigNumber(2, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(2, expectedSupplyBalanceOnPool1)
      );
      expect(
        removeDigitsBigNumber(
          2,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceOnPool1));

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount, 0);

      // Borrowers borrows supplier1 amount
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, supplyAmount, 0);

      // Check supplier1 balances
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const supplyP2pExchangeRate1 = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);
      const expectedSupplyBalanceOnPool2 = expectedSupplyBalanceOnPool1.sub(underlyingToScaledBalance(supplyAmount, normalizedIncome2));
      const expectedSupplyBalanceInP2P2 = underlyingToP2PUnit(supplyAmount, supplyP2pExchangeRate1);
      const supplyBalanceOnPool2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .onPool;
      const supplyBalanceInP2P2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .inP2P;
      expect(removeDigitsBigNumber(3, supplyBalanceOnPool2)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool2));
      expect(removeDigitsBigNumber(3, supplyBalanceInP2P2)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceInP2P2));

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(
        roundBigNumber(11, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P)
      ).to.equal(roundBigNumber(11, expectedBorrowBalanceInP2P1));

      // Compare remaining to withdraw and the aToken contract balance
      await marketsManagerForAave.connect(owner).updateRates(config.tokens.aDai.address);
      const supplyP2pExchangeRate2 = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);
      const supplyP2pExchangeRate3 = computeNewMorphoExchangeRate(
        supplyP2pExchangeRate2,
        await marketsManagerForAave.supplyP2pSPY(config.tokens.aDai.address),
        1,
        0
      );
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnPool3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .onPool;
      const supplyBalanceInP2P3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .inP2P;
      const normalizedIncome3 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool3, normalizedIncome3);
      const amountToWithdraw = supplyBalanceOnPoolInUnderlying.add(p2pUnitToUnderlying(supplyBalanceInP2P3, supplyP2pExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnPoolInUnderlying);
      const aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(
        await aDaiToken.balanceOf(positionsManagerForAave.address),
        normalizedIncome3
      );
      expect(remainingToWithdraw).to.be.gt(aTokenContractBalanceInUnderlying);

      // Expected borrow balances
      const expectedMorphoBorrowBalance = remainingToWithdraw.add(aTokenContractBalanceInUnderlying).sub(supplyBalanceOnPoolInUnderlying);

      // Withdraw
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, supplyAmount);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const expectedBorrowerBorrowBalanceOnPool = underlyingToAdUnit(expectedMorphoBorrowBalance, normalizedVariableDebt);
      const borrowBalance = await variableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      // Check borrow balance of Morpho
      expect(removeDigitsBigNumber(11, borrowBalance)).to.equal(removeDigitsBigNumber(11, expectedMorphoBorrowBalance));

      // Check supplier1 underlying balance (same as before + small gains)
      expect(removeDigitsBigNumber(1, daiBalanceAfter2).gte(removeDigitsBigNumber(1, expectedDaiBalanceAfter2)));

      // Check supply balances of supplier1
      expect(
        removeDigitsBigNumber(
          1,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool
        )
      ).to.equal(0);
      expect(
        removeDigitsBigNumber(
          10,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P
        )
      ).to.equal(0);

      // Check borrow balances of borrower1
      expect(
        roundBigNumber(12, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool)
      ).to.equal(roundBigNumber(12, expectedBorrowerBorrowBalanceOnPool));
      expect(
        roundBigNumber(12, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P)
      ).to.equal(0);
    });

    it('Supplier should withdraw her liquidity while enough aDaiToken in peer-to-peer contract', async () => {
      const supplyAmount = utils.parseUnits('10');

      for (const supplier of suppliers) {
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(supplyAmount);
        await daiToken.connect(supplier).approve(positionsManagerForAave.address, supplyAmount);
        await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, supplyAmount, 0);
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
        const expectedSupplyBalanceOnPool = underlyingToScaledBalance(supplyAmount, normalizedIncome);
        expect(
          removeDigitsBigNumber(
            4,
            (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).onPool
          )
        ).to.equal(removeDigitsBigNumber(4, expectedSupplyBalanceOnPool));
      }

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount, 0);

      const previousSupplier1SupplyBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())
      ).onPool;

      // Borrowers borrows supplier1 amount
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, supplyAmount, 0);

      // Check supplier1 balances
      const supplyP2pExchangeRate1 = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      // Expected balances of supplier1
      const expectedSupplyBalanceOnPool2 = previousSupplier1SupplyBalanceOnPool.sub(
        underlyingToScaledBalance(supplyAmount, normalizedIncome2)
      );
      const expectedSupplyBalanceInP2P2 = underlyingToP2PUnit(supplyAmount, supplyP2pExchangeRate1);
      const supplyBalanceOnPool2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .onPool;
      const supplyBalanceInP2P2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .inP2P;
      expect(removeDigitsBigNumber(3, supplyBalanceOnPool2)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool2));
      expect(removeDigitsBigNumber(3, supplyBalanceInP2P2)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceInP2P2));

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(
        removeDigitsBigNumber(
          3,
          (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(3, expectedBorrowBalanceInP2P1));

      // Compare remaining to withdraw and the aToken contract balance
      await marketsManagerForAave.connect(owner).updateRates(config.tokens.aDai.address);
      const supplyP2pExchangeRate2 = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);
      const supplyP2pExchangeRate3 = computeNewMorphoExchangeRate(
        supplyP2pExchangeRate2,
        await marketsManagerForAave.supplyP2pSPY(config.tokens.aDai.address),
        1,
        0
      );
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnPool3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .onPool;
      const supplyBalanceInP2P3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .inP2P;
      const normalizedIncome3 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool3, normalizedIncome3);
      const amountToWithdraw = supplyBalanceOnPoolInUnderlying.add(p2pUnitToUnderlying(supplyBalanceInP2P3, supplyP2pExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnPoolInUnderlying);
      const aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(
        await aDaiToken.balanceOf(positionsManagerForAave.address),
        normalizedIncome3
      );
      expect(remainingToWithdraw).to.be.lt(aTokenContractBalanceInUnderlying);

      // supplier3 balances before the withdraw
      const supplier3SupplyBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())
      ).onPool;
      const supplier3SupplyBalanceInP2P = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())
      ).inP2P;

      // supplier2 balances before the withdraw
      const supplier2SupplyBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())
      ).onPool;
      const supplier2SupplyBalanceInP2P = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())
      ).inP2P;

      // borrower1 balances before the withdraw
      const borrower1BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())
      ).onPool;
      const borrower1BorrowBalanceInP2P = (
        await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())
      ).inP2P;

      // Withdraw
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, supplyAmount);
      const normalizedIncome4 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const borrowBalance = await variableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      const supplier2SupplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplier2SupplyBalanceOnPool, normalizedIncome4);
      const amountToMove = bigNumberMin(supplier2SupplyBalanceOnPoolInUnderlying, remainingToWithdraw);
      const supplyP2pExchangeRate4 = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);
      const expectedSupplier2SupplyBalanceOnPool = supplier2SupplyBalanceOnPool.sub(
        underlyingToScaledBalance(amountToMove, normalizedIncome4)
      );
      const expectedSupplier2SupplyBalanceInP2P = supplier2SupplyBalanceInP2P.add(
        underlyingToP2PUnit(amountToMove, supplyP2pExchangeRate4)
      );

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check supplier1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check supply balances of supplier1
      expect(
        removeDigitsBigNumber(
          1,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool
        )
      ).to.equal(0);
      expect(
        removeDigitsBigNumber(
          5,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P
        )
      ).to.equal(0);

      // Check supply balances of supplier2: supplier2 should have replaced supplier1
      expect(
        removeDigitsBigNumber(
          4,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(4, expectedSupplier2SupplyBalanceOnPool));
      expect(
        removeDigitsBigNumber(
          7,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(7, expectedSupplier2SupplyBalanceInP2P));

      // Check supply balances of supplier3: supplier3 balances should not move
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).onPool).to.equal(
        supplier3SupplyBalanceOnPool
      );
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).inP2P).to.equal(
        supplier3SupplyBalanceInP2P
      );

      // Check borrow balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(
        borrower1BorrowBalanceOnPool
      );
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(
        borrower1BorrowBalanceInP2P
      );
    });

    it('Borrower in peer-to-peer only, should be able to repay all borrow amount', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount, 0);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.div(2);

      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount, 0);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow, 0);

      const borrowerBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .inP2P;
      const borrowP2pSPY = await marketsManagerForAave.borrowP2pSPY(config.tokens.aDai.address);
      await marketsManagerForAave.updateRates(config.tokens.aDai.address);
      const borrowP2pExchangeRateBefore = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);
      const borrowP2pExchangeRate: BigNumber = computeNewMorphoExchangeRate(
        borrowP2pExchangeRateBefore,
        borrowP2pSPY,
        AVERAGE_BLOCK_TIME,
        0
      );
      const toRepay = p2pUnitToUnderlying(borrowerBalanceInP2P, borrowP2pExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoScaledBalance = await aDaiToken.scaledBalanceOf(positionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);

      // revert here
      await positionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedMorphoScaledBalance = previousMorphoScaledBalance.add(underlyingToScaledBalance(toRepay, normalizedIncome));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      // Commented here due to the pow function issue
      // expect(removeDigitsBigNumber(1, (await positionsManagerForAave.borrowBalanceInOf(borrower1.getAddress())).inP2P)).to.equal(0);

      // Check Morpho balances
      expect(removeDigitsBigNumber(3, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(3, expectedMorphoScaledBalance)
      );
      expect(await variableDebtDaiToken.balanceOf(positionsManagerForAave.address)).to.equal(0);
    });

    it('Borrower in peer-to-peer and on Aave, should be able to repay all borrow amount', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('100000000');
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount, 0);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount, 0);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.mul(2);
      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .onPool;
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow, 0);

      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedMorphoBorrowBalance1 = toBorrow.sub(scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome1));
      const morphoBorrowBalanceBefore1 = await variableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      expect(removeDigitsBigNumber(6, morphoBorrowBalanceBefore1)).to.equal(removeDigitsBigNumber(6, expectedMorphoBorrowBalance1));
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, amountToApprove);

      const borrowerBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .inP2P;
      const borrowP2pSPY = await marketsManagerForAave.borrowP2pSPY(config.tokens.aDai.address);
      const borrowP2pExchangeRateBefore = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);
      const borrowP2pExchangeRate = computeNewMorphoExchangeRate(borrowP2pExchangeRateBefore, borrowP2pSPY, AVERAGE_BLOCK_TIME * 2, 0);
      const borrowerBalanceInP2PInUnderlying = p2pUnitToUnderlying(borrowerBalanceInP2P, borrowP2pExchangeRate);

      // Compute how much to repay
      const normalizeVariableDebt1 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const borrowerBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .onPool;
      const toRepay = aDUnitToUnderlying(borrowerBalanceOnPool, normalizeVariableDebt1).add(borrowerBalanceInP2PInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoScaledBalance = await aDaiToken.scaledBalanceOf(positionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);
      await positionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedMorphoScaledBalance = previousMorphoScaledBalance.add(
        underlyingToScaledBalance(borrowerBalanceInP2PInUnderlying, normalizedIncome2)
      );

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())
      ).onPool;
      expect(removeDigitsBigNumber(2, borrower1BorrowBalanceOnPool)).to.equal(0);
      // WARNING: Commented here due to the pow function issue
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.be.lt(
        1000000000000
      );

      // Check Morpho balances
      expect(removeDigitsBigNumber(13, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(13, expectedMorphoScaledBalance)
      );
      // Issue here: we cannot access the most updated borrow balance as it's updated during the repayBorrow on Aave.
      // const expectedMorphoBorrowBalance2 = morphoBorrowBalanceBefore2.sub(borrowerBalanceOnPool.mul(normalizeVariableDebt2).div(WAD));
      // expect(removeDigitsBigNumber(3, await aToken.callStatic.borrowBalanceStored(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowBalance2));
    });

    it('Supplier should be connected to borrowers on pool when supplying', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const supplyAmount = utils.parseUnits('100');
      const borrowAmount = utils.parseUnits('30');

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount, 0);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, borrowAmount, 0);
      const borrower1BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())
      ).onPool;

      // borrower2 borrows
      await usdcToken.connect(borrower2).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower2).supply(config.tokens.aUsdc.address, collateralAmount, 0);
      await positionsManagerForAave.connect(borrower2).borrow(config.tokens.aDai.address, borrowAmount, 0);
      const borrower2BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower2.getAddress())
      ).onPool;

      // borrower3 borrows
      await usdcToken.connect(borrower3).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower3).supply(config.tokens.aUsdc.address, collateralAmount, 0);
      await positionsManagerForAave.connect(borrower3).borrow(config.tokens.aDai.address, borrowAmount, 0);
      const borrower3BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower3.getAddress())
      ).onPool;

      // supplier1 supply
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount, 0);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const supplyP2pExchangeRate = await marketsManagerForAave.supplyP2pExchangeRate(config.tokens.aDai.address);

      // Check balances
      const supplyBalanceInP2P = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .inP2P;
      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress()))
        .onPool;
      const underlyingMatched = aDUnitToUnderlying(
        borrower1BorrowBalanceOnPool.add(borrower2BorrowBalanceOnPool).add(borrower3BorrowBalanceOnPool),
        normalizedVariableDebt
      );
      const expectedSupplyBalanceInP2P = underlyingToAdUnit(underlyingMatched, supplyP2pExchangeRate);
      const expectedSupplyBalanceOnPool = underlyingToScaledBalance(supplyAmount.sub(underlyingMatched), normalizedIncome);
      expect(removeDigitsBigNumber(3, supplyBalanceInP2P)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceInP2P));
      expect(removeDigitsBigNumber(3, supplyBalanceOnPool)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool));
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower2.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower3.getAddress())).onPool).to.be.lte(1);
    });

    it('Borrower should be connected to suppliers on pool in peer-to-peer when borrowing', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('140'));
      const supplyAmount = utils.parseUnits('30');
      const borrowAmount = utils.parseUnits('100');

      // supplier1 supplies
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount, 0);
      const supplier1BorrowBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())
      ).onPool;

      // supplier2 supplies
      await daiToken.connect(supplier2).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier2).supply(config.tokens.aDai.address, supplyAmount, 0);
      const supplier2BorrowBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())
      ).onPool;

      // supplier3 supplies
      await daiToken.connect(supplier3).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier3).supply(config.tokens.aDai.address, supplyAmount, 0);
      const supplier3BorrowBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())
      ).onPool;

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount, 0);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, borrowAmount, 0);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const borrowP2pExchangeRate = await marketsManagerForAave.borrowP2pExchangeRate(config.tokens.aDai.address);

      // Check balances
      const borrowBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .inP2P;
      const borrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .onPool;
      const underlyingMatched = scaledBalanceToUnderlying(
        supplier1BorrowBalanceOnPool.add(supplier2BorrowBalanceOnPool).add(supplier3BorrowBalanceOnPool),
        normalizedIncome
      );
      const expectedBorrowBalanceInP2P = underlyingToP2PUnit(underlyingMatched, borrowP2pExchangeRate);
      const expectedBorrowBalanceOnPool = underlyingToAdUnit(borrowAmount.sub(underlyingMatched), normalizedVariableDebt);
      expect(removeDigitsBigNumber(7, borrowBalanceInP2P)).to.equal(removeDigitsBigNumber(7, expectedBorrowBalanceInP2P));
      expect(removeDigitsBigNumber(7, borrowBalanceOnPool)).to.equal(removeDigitsBigNumber(7, expectedBorrowBalanceOnPool));
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.cDai.address, supplier2.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.cDai.address, supplier3.getAddress())).onPool).to.be.lte(1);
    });

    it('Borrower should be able to repay all (on Pool and in P2P)', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      const toBorrow = utils.parseUnits('50');
      const hugeAmount = utils.parseUnits('100');
      const toSupply = utils.parseUnits('20');

      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, toSupply, 0);
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow, 0);

      // Repay all
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, hugeAmount);
      await positionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, MAX_INT);
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(0);
    });

    it('Should be able to withdraw all (on Pool and in P2P)', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      const toBorrow = utils.parseUnits('50');
      const toSupply = utils.parseUnits('20');

      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, toSupply, 0);
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow, 0);

      // Withdraw all
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, MAX_INT);
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool).to.equal(0);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P).to.equal(0);
      expect(daiBalanceAfter).to.be.gt(daiBalanceBefore);
    });
  });

  describe('Test liquidation', () => {
    it('Borrower should be liquidated while supply (collateral) is only on Aave', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('contracts/aave/test/SimplePriceOracle.sol:SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await lendingPoolAddressesProvider.owner();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      // Deposit
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);
      const collateralBalanceInScaledBalance = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).onPool;
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
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

      // Borrow DAI
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow, 0);
      const collateralBalanceBefore = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress()))
        .onPool;
      const borrowBalanceBefore = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .onPool;

      // Set price oracle
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(priceOracle.address);
      priceOracle.setDirectPrice(config.tokens.dai.address, WAD.mul(11).div(10));
      priceOracle.setDirectPrice(config.tokens.usdc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.wbtc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.usdt.address, WAD);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate
      const toRepay = maxToBorrow.div(2);
      await daiToken.connect(liquidator).approve(positionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await positionsManagerForAave
        .connect(liquidator)
        .liquidate(config.tokens.aDai.address, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const cUsdNormalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const { liquidationBonus } = await protocolDataProvider.getReserveConfigurationData(config.tokens.usdc.address);
      const collateralAssetPrice = await priceOracle.getAssetPrice(config.tokens.usdc.address);
      const borrowedAssetPrice = await priceOracle.getAssetPrice(config.tokens.dai.address);
      const amountToSeize = toRepay
        .mul(borrowedAssetPrice)
        .div(BigNumber.from(10).pow(daiDecimals))
        .mul(BigNumber.from(10).pow(usdcDecimals))
        .div(collateralAssetPrice)
        .mul(liquidationBonus)
        .div(10000);
      const expectedCollateralBalanceAfter = collateralBalanceBefore.sub(underlyingToScaledBalance(amountToSeize, cUsdNormalizedIncome));
      const expectedBorrowBalanceAfter = borrowBalanceBefore.sub(underlyingToAdUnit(toRepay, normalizedVariableDebt));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check balances
      expect(
        removeDigitsBigNumber(
          6,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(6, expectedCollateralBalanceAfter));
      expect(
        removeDigitsBigNumber(
          3,
          (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(3, expectedBorrowBalanceAfter));
      expect(removeDigitsBigNumber(2, usdcBalanceAfter)).to.equal(removeDigitsBigNumber(2, expectedUsdcBalanceAfter));
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });

    it('Borrower should be liquidated while supply (collateral) is on Aave and in peer-to-peer', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('contracts/aave/test/SimplePriceOracle.sol:SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await lendingPoolAddressesProvider.owner();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(oracle.address);

      // supplier1 supplies DAI
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, utils.parseUnits('200'));
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, utils.parseUnits('200'), 0);

      // borrower1 supplies USDC as supply (collateral)
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount, 0);

      // borrower2 borrows part of supply of borrower1 -> borrower1 has supply in peer-to-peer and on Aave
      const toBorrow = amount;
      const toSupply = BigNumber.from(10).pow(8);
      await wbtcToken.connect(borrower2).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(borrower2).supply(config.tokens.aWbtc.address, toSupply, 0);
      await positionsManagerForAave.connect(borrower2).borrow(config.tokens.aUsdc.address, toBorrow, 0);

      // borrower1 borrows DAI
      const usdcNormalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const borrowP2pUsdcExchangeRate1 = await marketsManagerForAave.borrowP2pExchangeRate(config.tokens.aUsdc.address);
      const supplyBalanceOnPool1 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress()))
        .onPool;
      const supplyBalanceInP2P1 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress()))
        .inP2P;
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool1, usdcNormalizedIncome1);
      const supplyBalanceMorphoInUnderlying = p2pUnitToUnderlying(supplyBalanceInP2P1, borrowP2pUsdcExchangeRate1);
      const supplyBalanceInUnderlying = supplyBalanceOnPoolInUnderlying.add(supplyBalanceMorphoInUnderlying);
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(config.tokens.dai.address);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.usdc.address);
      const usdcDecimals = await usdcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(config.tokens.dai.address);
      const daiDecimals = await daiToken.decimals();
      const maxToBorrow = supplyBalanceInUnderlying
        .mul(usdcPrice)
        .div(BigNumber.from(10).pow(usdcDecimals))
        .mul(BigNumber.from(10).pow(daiDecimals))
        .div(daiPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow, 0);
      const collateralBalanceOnPoolBefore = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).onPool;
      const collateralBalanceInP2PBefore = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).inP2P;
      const borrowBalanceInP2PBefore = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress()))
        .inP2P;

      // Set price oracle
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(priceOracle.address);
      priceOracle.setDirectPrice(config.tokens.dai.address, WAD.mul(11).div(10));
      priceOracle.setDirectPrice(config.tokens.usdc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.wbtc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.usdt.address, WAD);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // liquidator liquidates borrower1's position
      const toRepay = maxToBorrow.mul(LIQUIDATION_CLOSE_FACTOR_PERCENT).div(10000);
      await daiToken.connect(liquidator).approve(positionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await positionsManagerForAave
        .connect(liquidator)
        .liquidate(config.tokens.aDai.address, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const borrowP2pDaiExchangeRate = await marketsManagerForAave.borrowP2pExchangeRate(config.tokens.aDai.address);
      const usdcNormalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const { liquidationBonus } = await protocolDataProvider.getReserveConfigurationData(config.tokens.usdc.address);
      const collateralAssetPrice = await priceOracle.getAssetPrice(config.tokens.usdc.address);
      const borrowedAssetPrice = await priceOracle.getAssetPrice(config.tokens.dai.address);
      const amountToSeize = toRepay
        .mul(borrowedAssetPrice)
        .mul(BigNumber.from(10).pow(usdcDecimals))
        .div(BigNumber.from(10).pow(daiDecimals))
        .div(collateralAssetPrice)
        .mul(liquidationBonus)
        .div(PERCENT_BASE);
      const expectedCollateralBalanceInP2PAfter = collateralBalanceInP2PBefore.sub(
        amountToSeize.sub(scaledBalanceToUnderlying(collateralBalanceOnPoolBefore, usdcNormalizedIncome))
      );
      const expectedBorrowBalanceInP2PAfter = borrowBalanceInP2PBefore.sub(underlyingToP2PUnit(toRepay, borrowP2pDaiExchangeRate));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check liquidatee balances
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(
        removeDigitsBigNumber(
          2,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(2, expectedCollateralBalanceInP2PAfter));
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(
        removeDigitsBigNumber(
          3,
          (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(3, expectedBorrowBalanceInP2PAfter));

      // Check liquidator balances
      let diff;
      if (usdcBalanceAfter.gt(expectedUsdcBalanceAfter)) diff = usdcBalanceAfter.sub(expectedUsdcBalanceAfter);
      else diff = expectedUsdcBalanceAfter.sub(usdcBalanceAfter);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });
  });

  describe('Cap Value', () => {
    it('Should be possible to supply up to cap value', async () => {
      const newCapValue = utils.parseUnits('2');
      const amount = utils.parseUnits('2');
      await marketsManagerForAave.connect(owner).updateCapValue(config.tokens.aDai.address, newCapValue);

      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, utils.parseUnits('3'));
      expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount, 0)).not.to.be.reverted;
      expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, utils.parseUnits('100'), 0)).to.be.reverted;
      expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, 1, 0)).to.be.reverted;
    });
  });

  describe('Test claiming rewards', () => {
    it('Anyone should be able to claim rewards on several markets', async () => {
      const toSupply = utils.parseUnits('100');
      const toBorrow = to6Decimals(utils.parseUnits('50'));
      const rewardTokenBalanceBefore = await wmaticToken.balanceOf(owner.getAddress());
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, toSupply, 0);
      await positionsManagerForAave.connect(supplier1).borrow(config.tokens.aUsdc.address, toBorrow, 0);

      // Mine 1000 blocks
      for (let i = 0; i < 1000; i++) {
        await hre.network.provider.send('evm_mine', []);
      }

      await positionsManagerForAave.connect(supplier1).claimRewards(config.tokens.variableDebtUsdc.address);
      const rewardTokenBalanceAfter1 = await wmaticToken.balanceOf(owner.getAddress());
      expect(rewardTokenBalanceAfter1).to.be.gt(rewardTokenBalanceBefore);
      await positionsManagerForAave.connect(borrower1).claimRewards(config.tokens.aDai.address);
      const rewardTokenBalanceAfter2 = await wmaticToken.balanceOf(owner.getAddress());
      expect(rewardTokenBalanceAfter2).to.be.gt(rewardTokenBalanceAfter1);
    });
  });

  describe.only('Test claiming fees', () => {
    it('DAO should be able to withdraw fees', async () => {
      await marketsManagerForAave.connect(owner).setFee('100000000000000000000000000'); // 10%

      const toSupply = utils.parseUnits('100');
      const toBorrow = utils.parseUnits('50');
      const daoBalanceBefore = await daiToken.balanceOf(owner.getAddress());
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, toSupply, 0);
      await positionsManagerForAave.connect(supplier1).borrow(config.tokens.aDai.address, toBorrow, 0);

      // wait 10 years
      await hre.network.provider.send('evm_increaseTime', [315360000]);

      await positionsManagerForAave.connect(owner).claimFees(config.tokens.aDai.address);
      const daoBalanceAfter = await daiToken.balanceOf(owner.getAddress());
      expect(daoBalanceAfter).to.be.gt(daoBalanceBefore);
    });
  });

  describe('Test attacks', () => {
    it('Should not be possible to withdraw amount if the position turns to be under-collateralized', async () => {
      const toSupply = utils.parseUnits('100');
      const toBorrow = to6Decimals(utils.parseUnits('50'));

      // supplier1 deposits collateral
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, toSupply, 0);

      // supplier2 deposits collateral
      await daiToken.connect(supplier2).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(supplier2).supply(config.tokens.aDai.address, toSupply, 0);

      // supplier1 tries to withdraw more than allowed
      await positionsManagerForAave.connect(supplier1).borrow(config.tokens.aUsdc.address, toBorrow, 0);
      expect(positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, toSupply)).to.be.reverted;
    });

    it('Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract', async () => {
      const toSupply = utils.parseUnits('100');
      const toSupplyCollateral = to6Decimals(utils.parseUnits('200'));
      const toBorrow = toSupply;

      // attacker sends aToken to positionsManager contract
      await daiToken.connect(attacker).approve(lendingPool.address, toSupply);
      const attackerAddress = await attacker.getAddress();
      await lendingPool.connect(attacker).deposit(daiToken.address, toSupply, attackerAddress, 0);
      await aDaiToken.connect(attacker).transfer(positionsManagerForAave.address, toSupply);

      // supplier1 deposits collateral
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, toSupply, 0);

      // borrower1 deposits collateral
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, toSupplyCollateral);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, toSupplyCollateral, 0);

      // supplier1 tries to withdraw
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow, 0);
      await expect(positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, toSupply)).to.not.be.reverted;
    });
  });
});
