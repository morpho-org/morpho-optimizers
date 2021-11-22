require('dotenv').config({ path: '.env.local' });
const { utils, BigNumber } = require('ethers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const hre = require('hardhat');
const config = require(`@config/${process.env.NETWORK}-config.json`);
const { MAX_INT, removeDigitsBigNumber, bigNumberMin, to6Decimals, getTokens } = require('./utils/common-helpers');
const {
  RAY,
  underlyingToScaledBalance,
  scaledBalanceToUnderlying,
  underlyingToP2PUnit,
  p2pUnitToUnderlying,
  underlyingToAdUnit,
  aDUnitToUnderlying,
  computeNewMorphoExchangeRate,
} = require('./utils/aave-helpers');

describe('PositionsManagerForAave Contract', () => {
  const LIQUIDATION_CLOSE_FACTOR_PERCENT = BigNumber.from(5000);
  const SECOND_PER_YEAR = BigNumber.from(31536000);
  const PERCENT_BASE = BigNumber.from(10000);
  const AVERAGE_BLOCK_TIME = 2;

  let aUsdcToken;
  let aDaiToken;
  let aUsdtToken;
  let aWbtcToken;
  let daiToken;
  let usdtToken;
  let wbtcToken;
  let PositionsManagerForAave;
  let positionsManagerForAave;
  let marketsManagerForAave;
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
  let snapshotId;

  const initialize = async () => {
    {
      // Users
      signers = await ethers.getSigners();
      [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
      suppliers = [supplier1, supplier2, supplier3];
      borrowers = [borrower1, borrower2, borrower3];

      const RedBlackBinaryTree = await ethers.getContractFactory('contracts/aave/libraries/RedBlackBinaryTree.sol:RedBlackBinaryTree');
      const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
      await redBlackBinaryTree.deployed();

      const UpdatePositions = await ethers.getContractFactory('contracts/aave/UpdatePositions.sol:UpdatePositions', {
        libraries: {
          RedBlackBinaryTree: redBlackBinaryTree.address,
        },
      });
      const updatePositions = await UpdatePositions.deploy();
      await updatePositions.deployed();

      // Deploy contracts
      const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
      marketsManagerForAave = await MarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
      await marketsManagerForAave.deployed();

      PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave', {
        libraries: {
          RedBlackBinaryTree: redBlackBinaryTree.address,
        },
      });
      positionsManagerForAave = await PositionsManagerForAave.deploy(marketsManagerForAave.address, config.aave.lendingPoolAddressesProvider.address, updatePositions.address);
      fakeAavePositionsManager = await PositionsManagerForAave.deploy(marketsManagerForAave.address, config.aave.lendingPoolAddressesProvider.address, updatePositions.address);
      await positionsManagerForAave.deployed();
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
      wbtcToken = await getTokens('0xdc9232e2df177d7a12fdff6ecbab114e2231198d', 'whale', signers, config.tokens.wbtc, BigNumber.from(10).pow(8));
      wmaticToken = await getTokens('0xadbf1854e5883eb8aa7baf50705338739e558e5b', 'whale', signers, config.tokens.wmatic, utils.parseUnits('100'));

      underlyingThreshold = utils.parseUnits('1');

      // Create and list markets
      await marketsManagerForAave.connect(owner).setPositionsManager(positionsManagerForAave.address);
      await marketsManagerForAave.connect(owner).setLendingPool();
      await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, utils.parseUnits('1'), MAX_INT);
      await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(utils.parseUnits('1')), MAX_INT);
      await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address, BigNumber.from(10).pow(4), MAX_INT);
      await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address, to6Decimals(utils.parseUnits('1')), MAX_INT);
      await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address, utils.parseUnits('1'), MAX_INT);
    }
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
      // Calculate p2pSPY
      const reserveData = await lendingPool.getReserveData(config.tokens.dai.address);
      const currentLiquidityRate = reserveData.currentLiquidityRate;
      const currentVariableBorrowRate = reserveData.currentVariableBorrowRate;
      const expectedSPY = currentLiquidityRate.add(currentVariableBorrowRate).div(2).div(SECOND_PER_YEAR);
      expect(await marketsManagerForAave.p2pSPY(config.tokens.aDai.address)).to.equal(expectedSPY);
      expect(await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address)).to.be.equal(RAY);

      // Thresholds
      underlyingThreshold = await positionsManagerForAave.threshold(config.tokens.aDai.address);
      expect(underlyingThreshold).to.be.equal(utils.parseUnits('1'));
    });
  });

  describe('Governance functions', () => {
    it('Should revert when at least when a market in input is not a real market', async () => {
      expect(marketsManagerForAave.connect(owner).createMarket(config.tokens.usdt.address, utils.parseUnits('1'))).to.be.reverted;
    });

    it('Only Owner should be able to create markets in peer-to-peer', async () => {
      expect(marketsManagerForAave.connect(supplier1).createMarket(config.tokens.aWeth.address, utils.parseUnits('1'), MAX_INT)).to.be.reverted;
      expect(marketsManagerForAave.connect(borrower1).createMarket(config.tokens.aWeth.address, utils.parseUnits('1')), MAX_INT).to.be.reverted;
      expect(marketsManagerForAave.connect(owner).createMarket(config.tokens.aWeth.address, utils.parseUnits('1')), MAX_INT).not.be.reverted;
    });

    it('marketsManagerForAave should not be changed after already set by Owner', async () => {
      expect(marketsManagerForAave.connect(owner).setPositionsManager(fakeAavePositionsManager.address)).to.be.reverted;
    });

    it('Only Owner should be able to update thresholds', async () => {
      const newThreshold = utils.parseUnits('2');
      await marketsManagerForAave.connect(owner).updateThreshold(config.tokens.aUsdc.address, newThreshold);
      expect(await positionsManagerForAave.threshold(config.tokens.aUsdc.address)).to.be.equal(newThreshold);

      // Other accounts than Owner
      await expect(marketsManagerForAave.connect(supplier1).updateThreshold(config.tokens.aUsdc.address, newThreshold)).to.be.reverted;
      await expect(marketsManagerForAave.connect(borrower1).updateThreshold(config.tokens.aUsdc.address, newThreshold)).to.be.reverted;
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
      await marketsManagerForAave.connect(owner).createMarket(config.tokens.aAave.address, utils.parseUnits('1'), MAX_INT);
      expect(await marketsManagerForAave.isCreated(config.tokens.aAave.address)).to.be.true;
      expect(await marketsManagerForAave.p2pSPY(config.tokens.aAave.address)).to.equal(expectedSPY);
      expect(await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aAave.address)).to.equal(RAY);
    });

    it('Should update NMAX', async () => {
      const newNMAX = BigNumber.from(3000);
      expect(marketsManagerForAave.connect(supplier1).setMaxNumberOfUsersInTree(newNMAX)).to.be.reverted;
      expect(marketsManagerForAave.connect(borrower1).setMaxNumberOfUsersInTree(newNMAX)).to.be.reverted;
      expect(positionsManagerForAave.connect(owner).setMaxNumberOfUsersInTree(newNMAX)).to.be.reverted;
      await marketsManagerForAave.connect(owner).setMaxNumberOfUsersInTree(newNMAX);
      expect(await positionsManagerForAave.NMAX()).to.equal(newNMAX);
    });
  });

  describe('Suppliers on Aave (no borrowers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool).to.equal(0);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should revert when supply less than the required threshold', async () => {
      await expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, underlyingThreshold.sub(1))).to.be.reverted;
    });

    it('Should have the correct balances after supply', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedSupplyBalanceOnPool = underlyingToScaledBalance(amount, normalizedIncome);
      expect((await aDaiToken.balanceOf(positionsManagerForAave.address)) - amount).to.be.lte(10);
      // expect(await aDaiToken.balanceOf(positionsManagerForAave.address)).to.equal(amount);
      expect(removeDigitsBigNumber(1, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(1, expectedSupplyBalanceOnPool)
      );
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P).to.equal(0);
    });

    it('Should be able to withdraw ERC20 right after supply up to max supply balance', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(supplier1.getAddress());
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));

      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const toWithdraw1 = scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome1);

      // TODO: improve this test to prevent attacks
      await expect(positionsManagerForAave.connect(supplier1).withdraw(toWithdraw1.add(utils.parseUnits('0.001')).toString())).to.be.reverted;

      // Here we must calculate the next normalized income
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const toWithdraw2 = scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome2);
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, toWithdraw2);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());
      // Check ERC20 balance
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1.sub(amount).add(toWithdraw2));

      // Check aToken left are only dust in supply balance
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool).to.be.lt(BigNumber.from(10).pow(12));
      await expect(positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, utils.parseUnits('0.001'))).to.be.reverted;
    });

    it('Should be able to supply more ERC20 after already having supply ERC20', async () => {
      const amount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('10').mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(supplier1.getAddress());

      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, amountToApprove);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(supplier1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check supply balance
      const expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(amount, normalizedIncome1);
      const expectedSupplyBalanceOnPool2 = underlyingToScaledBalance(amount, normalizedIncome2);
      const expectedSupplyBalanceOnPool = expectedSupplyBalanceOnPool1.add(expectedSupplyBalanceOnPool2);
      expect(removeDigitsBigNumber(3, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool));
      expect(removeDigitsBigNumber(2, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(2, expectedSupplyBalanceOnPool)
      );
    });

    it('Several suppliers should be able to supply and have the correct balances', async () => {
      const amount = utils.parseUnits('10');
      let expectedScaledBalance = BigNumber.from(0);

      for (const i in suppliers) {
        const supplier = suppliers[i];
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(supplier).approve(positionsManagerForAave.address, amount);
        await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, amount);
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
        expect(removeDigitsBigNumber(2, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).onPool)).to.equal(
          removeDigitsBigNumber(2, expectedSupplyBalanceOnPool)
        );
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
      await expect(positionsManagerForAave.connect(supplier1).borrow(config.tokens.aDai.address, amount)).to.be.reverted;
    });

    it('Should be able to borrow on Aave after providing collateral up to max', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool;
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
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);

      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      const borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool, normalizedVariableDebt);
      let diff;
      if (borrowBalanceOnPoolInUnderlying.gt(maxToBorrow)) diff = borrowBalanceOnPoolInUnderlying.sub(underlyingToAdUnit(maxToBorrow, normalizedVariableDebt));
      else diff = maxToBorrow.sub(borrowBalanceOnPoolInUnderlying);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);
      // Check Morpho balances
      expect(await daiToken.balanceOf(positionsManagerForAave.address)).to.equal(0);
      expect(await stableDebtDaiToken.balanceOf(positionsManagerForAave.address)).to.equal(maxToBorrow);
    });

    it('Should not be able to borrow more than max allowed given an amount of collateral', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool;
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
        await positionsManagerForAave.connect(borrower).supply(config.tokens.aUsdc.address, collateralAmount);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await positionsManagerForAave.connect(borrower).borrow(config.tokens.aDai.address, borrowedAmount);
        // We have one block delay from Aave
        const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
        expectedMorphoBorrowBalance = expectedMorphoBorrowBalance.mul(normalizedVariableDebt).div(previousNormalizedVariableDebt).add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        const borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower.getAddress())).onPool, normalizedVariableDebt);
        let diff;
        if (borrowBalanceOnPoolInUnderlying.gt(borrowedAmount)) diff = borrowBalanceOnPoolInUnderlying.sub(borrowedAmount);
        else diff = borrowedAmount.sub(borrowBalanceOnPoolInUnderlying);
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        // Update previous borrow index
        previousNormalizedVariableDebt = normalizedVariableDebt;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(positionsManagerForAave.address)).to.equal(0);
      expect(removeDigitsBigNumber(2, await stableDebtDaiToken.balanceOf(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(2, expectedMorphoBorrowBalance));
    });

    it('Borrower should be able to repay less than what is on Aave', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInScaledBalance = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool;
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
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const borrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;
      const normalizeVariableDebt1 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(borrowBalanceOnPool, normalizeVariableDebt1);
      const toRepay = borrowBalanceOnPoolInUnderlying.div(2);
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);
      await positionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const normalizeVariableDebt2 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      const expectedBalanceOnPool = borrowBalanceOnPool.sub(underlyingToAdUnit(borrowBalanceOnPoolInUnderlying.div(2), normalizeVariableDebt2));
      expect(removeDigitsBigNumber(1, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(1, expectedBalanceOnPool)
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
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(supplier1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(supplyAmount, normalizedIncome1);
      expect(removeDigitsBigNumber(2, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceOnPool1));
      expect(removeDigitsBigNumber(2, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(2, expectedSupplyBalanceOnPool1)
      );

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);

      // Borrowers borrows supplier1 amount
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, supplyAmount);

      // Check supplier1 balances
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const p2pExchangeRate1 = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
      const expectedSupplyBalanceOnPool2 = expectedSupplyBalanceOnPool1.sub(underlyingToScaledBalance(supplyAmount, normalizedIncome2));
      const expectedSupplyBalanceInP2P2 = underlyingToP2PUnit(supplyAmount, p2pExchangeRate1);
      const supplyBalanceOnPool2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;
      const supplyBalanceInP2P2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      expect(removeDigitsBigNumber(3, supplyBalanceOnPool2)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceOnPool2));
      expect(removeDigitsBigNumber(3, supplyBalanceInP2P2)).to.equal(removeDigitsBigNumber(3, expectedSupplyBalanceInP2P2));

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(removeDigitsBigNumber(2, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(2, expectedBorrowBalanceInP2P1)
      );

      // Compare remaining to withdraw and the aToken contract balance
      await marketsManagerForAave.connect(owner).updateP2PUnitExchangeRate(config.tokens.aDai.address);
      const p2pExchangeRate2 = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
      const p2pExchangeRate3 = computeNewMorphoExchangeRate(p2pExchangeRate2, await marketsManagerForAave.p2pSPY(config.tokens.aDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnPool3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;
      const supplyBalanceInP2P3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      const normalizedIncome3 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool3, normalizedIncome3);
      const amountToWithdraw = supplyBalanceOnPoolInUnderlying.add(p2pUnitToUnderlying(supplyBalanceInP2P3, p2pExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnPoolInUnderlying);
      const aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(await aDaiToken.balanceOf(positionsManagerForAave.address), normalizedIncome3);
      expect(remainingToWithdraw).to.be.gt(aTokenContractBalanceInUnderlying);

      // Expected borrow balances
      const expectedMorphoBorrowBalance = remainingToWithdraw.add(aTokenContractBalanceInUnderlying).sub(supplyBalanceOnPoolInUnderlying);

      // Withdraw
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, amountToWithdraw);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const expectedBorrowerBorrowBalanceOnPool = underlyingToAdUnit(expectedMorphoBorrowBalance, normalizedVariableDebt);
      const borrowBalance = await stableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      // Check borrow balance of Morpho
      expect(removeDigitsBigNumber(11, borrowBalance)).to.equal(removeDigitsBigNumber(11, expectedMorphoBorrowBalance));

      // Check supplier1 underlying balance
      expect(removeDigitsBigNumber(1, daiBalanceAfter2)).to.equal(removeDigitsBigNumber(1, expectedDaiBalanceAfter2));

      // Check supply balances of supplier1
      expect(removeDigitsBigNumber(1, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool)).to.equal(0);
      expect(removeDigitsBigNumber(9, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P)).to.equal(0);

      // Check borrow balances of borrower1
      expect(removeDigitsBigNumber(11, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(11, expectedBorrowerBorrowBalanceOnPool)
      );
      expect(removeDigitsBigNumber(9, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P)).to.equal(0);
    });

    it('Supplier should withdraw her liquidity while enough aDaiToken in peer-to-peer contract', async () => {
      const supplyAmount = utils.parseUnits('10');
      let supplier;

      for (const i in suppliers) {
        supplier = suppliers[i];
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(supplyAmount);
        await daiToken.connect(supplier).approve(positionsManagerForAave.address, supplyAmount);
        await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, supplyAmount);
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
        const expectedSupplyBalanceOnPool = underlyingToScaledBalance(supplyAmount, normalizedIncome);
        expect(removeDigitsBigNumber(4, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier.getAddress())).onPool)).to.equal(
          removeDigitsBigNumber(4, expectedSupplyBalanceOnPool)
        );
      }

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);

      const previousSupplier1SupplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;

      // Borrowers borrows supplier1 amount
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, supplyAmount);

      // Check supplier1 balances
      const p2pExchangeRate1 = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      // Expected balances of supplier1
      const expectedSupplyBalanceOnPool2 = previousSupplier1SupplyBalanceOnPool.sub(underlyingToScaledBalance(supplyAmount, normalizedIncome2));
      const expectedSupplyBalanceInP2P2 = underlyingToP2PUnit(supplyAmount, p2pExchangeRate1);
      const supplyBalanceOnPool2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;
      const supplyBalanceInP2P2 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      expect(removeDigitsBigNumber(2, supplyBalanceOnPool2)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceOnPool2));
      expect(removeDigitsBigNumber(2, supplyBalanceInP2P2)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceInP2P2));

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(removeDigitsBigNumber(2, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(2, expectedBorrowBalanceInP2P1)
      );

      // Compare remaining to withdraw and the aToken contract balance
      await marketsManagerForAave.connect(owner).updateP2PUnitExchangeRate(config.tokens.aDai.address);
      const p2pExchangeRate2 = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
      const p2pExchangeRate3 = computeNewMorphoExchangeRate(p2pExchangeRate2, await marketsManagerForAave.p2pSPY(config.tokens.aDai.address), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnPool3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;
      const supplyBalanceInP2P3 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      const normalizedIncome3 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool3, normalizedIncome3);
      const amountToWithdraw = supplyBalanceOnPoolInUnderlying.add(p2pUnitToUnderlying(supplyBalanceInP2P3, p2pExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnPoolInUnderlying);
      const aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(await aDaiToken.balanceOf(positionsManagerForAave.address), normalizedIncome3);
      expect(remainingToWithdraw).to.be.lt(aTokenContractBalanceInUnderlying);

      // supplier3 balances before the withdraw
      const supplier3SupplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).onPool;
      const supplier3SupplyBalanceInP2P = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).inP2P;

      // supplier2 balances before the withdraw
      const supplier2SupplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).onPool;
      const supplier2SupplyBalanceInP2P = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).inP2P;

      // borrower1 balances before the withdraw
      const borrower1BorrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;
      const borrower1BorrowBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;

      // Withdraw
      await positionsManagerForAave.connect(supplier1).withdraw(config.tokens.aDai.address, amountToWithdraw);
      const normalizedIncome4 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const borrowBalance = await stableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      const supplier2SupplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplier2SupplyBalanceOnPool, normalizedIncome4);
      const amountToMove = bigNumberMin(supplier2SupplyBalanceOnPoolInUnderlying, remainingToWithdraw);
      const p2pExchangeRate4 = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
      const expectedSupplier2SupplyBalanceOnPool = supplier2SupplyBalanceOnPool.sub(underlyingToScaledBalance(amountToMove, normalizedIncome4));
      const expectedSupplier2SupplyBalanceInP2P = supplier2SupplyBalanceInP2P.add(underlyingToP2PUnit(amountToMove, p2pExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check supplier1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check supply balances of supplier1
      expect(removeDigitsBigNumber(1, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool)).to.equal(0);
      expect(removeDigitsBigNumber(5, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P)).to.equal(0);

      // Check supply balances of supplier2: supplier2 should have replaced supplier1
      expect(removeDigitsBigNumber(4, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(4, expectedSupplier2SupplyBalanceOnPool)
      );
      expect(removeDigitsBigNumber(7, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(7, expectedSupplier2SupplyBalanceInP2P)
      );

      // Check supply balances of supplier3: supplier3 balances should not move
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).onPool).to.equal(supplier3SupplyBalanceOnPool);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).inP2P).to.equal(supplier3SupplyBalanceInP2P);

      // Check borrow balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(borrower1BorrowBalanceOnPool);
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.equal(borrower1BorrowBalanceInP2P);
    });

    it('Borrower in peer-to-peer only, should be able to repay all borrow amount', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.div(2);

      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow);

      const borrowerBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;
      const p2pSPY = await marketsManagerForAave.p2pSPY(config.tokens.aDai.address);
      await marketsManagerForAave.updateP2PUnitExchangeRate(config.tokens.aDai.address);
      const p2pUnitExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
      const p2pExchangeRate = computeNewMorphoExchangeRate(p2pUnitExchangeRate, p2pSPY, AVERAGE_BLOCK_TIME, 0).toString();
      const toRepay = p2pUnitToUnderlying(borrowerBalanceInP2P, p2pExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoScaledBalance = await aDaiToken.scaledBalanceOf(positionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);
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
      expect(removeDigitsBigNumber(3, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoScaledBalance));
      expect(await stableDebtDaiToken.balanceOf(positionsManagerForAave.address)).to.equal(0);
    });

    it('Borrower in peer-to-peer and on Aave, should be able to repay all borrow amount', async () => {
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('100000000');
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.mul(2);
      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, toBorrow);

      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedMorphoBorrowBalance1 = toBorrow.sub(scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome1));
      const morphoBorrowBalanceBefore1 = await stableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      expect(removeDigitsBigNumber(6, morphoBorrowBalanceBefore1)).to.equal(removeDigitsBigNumber(6, expectedMorphoBorrowBalance1));
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, amountToApprove);

      const borrowerBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;
      const p2pSPY = await marketsManagerForAave.p2pSPY(config.tokens.aDai.address);
      const p2pUnitExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
      const p2pExchangeRate = computeNewMorphoExchangeRate(p2pUnitExchangeRate, p2pSPY, AVERAGE_BLOCK_TIME * 2, 0).toString();
      const borrowerBalanceInP2PInUnderlying = p2pUnitToUnderlying(borrowerBalanceInP2P, p2pExchangeRate);

      // Compute how much to repay
      const normalizeVariableDebt1 = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const borrowerBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;
      const toRepay = aDUnitToUnderlying(borrowerBalanceOnPool, normalizeVariableDebt1).add(borrowerBalanceInP2PInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoScaledBalance = await aDaiToken.scaledBalanceOf(positionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);
      await positionsManagerForAave.connect(borrower1).repay(config.tokens.aDai.address, toRepay);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const expectedMorphoScaledBalance = previousMorphoScaledBalance.add(underlyingToScaledBalance(borrowerBalanceInP2PInUnderlying, normalizedIncome2));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;
      expect(removeDigitsBigNumber(2, borrower1BorrowBalanceOnPool)).to.equal(0);
      // WARNING: Commented here due to the pow function issue
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P).to.be.lt(1000000000000);

      // Check Morpho balances
      expect(removeDigitsBigNumber(13, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(13, expectedMorphoScaledBalance));
      // Issue here: we cannot access the most updated borrow balance as it's updated during the repayBorrow on Aave.
      // const expectedMorphoBorrowBalance2 = morphoBorrowBalanceBefore2.sub(borrowerBalanceOnPool.mul(normalizeVariableDebt2).div(SCALE));
      // expect(removeDigitsBigNumber(3, await aToken.callStatic.borrowBalanceStored(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowBalance2));
    });

    it('Supplier should be connected to borrowers on pool when supplying', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const supplyAmount = utils.parseUnits('100');
      const borrowAmount = utils.parseUnits('30');

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, borrowAmount);
      const borrower1BorrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;

      // borrower2 borrows
      await usdcToken.connect(borrower2).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower2).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower2).borrow(config.tokens.aDai.address, borrowAmount);
      const borrower2BorrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower2.getAddress())).onPool;

      // borrower3 borrows
      await usdcToken.connect(borrower3).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower3).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower3).borrow(config.tokens.aDai.address, borrowAmount);
      const borrower3BorrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower3.getAddress())).onPool;

      // supplier1 supply
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const p2pUnitExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);

      // Check balances
      const supplyBalanceInP2P = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).inP2P;
      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;
      const underlyingMatched = aDUnitToUnderlying(borrower1BorrowBalanceOnPool.add(borrower2BorrowBalanceOnPool).add(borrower3BorrowBalanceOnPool), normalizedVariableDebt);
      expectedSupplyBalanceInP2P = underlyingToAdUnit(underlyingMatched, p2pUnitExchangeRate);
      expectedSupplyBalanceOnPool = underlyingToScaledBalance(supplyAmount.sub(underlyingMatched), normalizedIncome);
      expect(removeDigitsBigNumber(2, supplyBalanceInP2P)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceInP2P));
      expect(removeDigitsBigNumber(2, supplyBalanceOnPool)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceOnPool));
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
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, supplyAmount);
      const supplier1BorrowBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier1.getAddress())).onPool;

      // supplier2 supplies
      await daiToken.connect(supplier2).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier2).supply(config.tokens.aDai.address, supplyAmount);
      const supplier2BorrowBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier2.getAddress())).onPool;

      // supplier3 supplies
      await daiToken.connect(supplier3).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier3).supply(config.tokens.aDai.address, supplyAmount);
      const supplier3BorrowBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aDai.address, supplier3.getAddress())).onPool;

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, borrowAmount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.dai.address);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(config.tokens.dai.address);
      const p2pUnitExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);

      // Check balances
      const borrowBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;
      const borrowBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;
      const underlyingMatched = scaledBalanceToUnderlying(supplier1BorrowBalanceOnPool.add(supplier2BorrowBalanceOnPool).add(supplier3BorrowBalanceOnPool), normalizedIncome);
      expectedBorrowBalanceInP2P = underlyingToP2PUnit(underlyingMatched, p2pUnitExchangeRate);
      expectedBorrowBalanceOnPool = underlyingToAdUnit(borrowAmount.sub(underlyingMatched), normalizedVariableDebt);
      expect(removeDigitsBigNumber(7, borrowBalanceInP2P)).to.equal(removeDigitsBigNumber(7, expectedBorrowBalanceInP2P));
      expect(removeDigitsBigNumber(7, borrowBalanceOnPool)).to.equal(removeDigitsBigNumber(7, expectedBorrowBalanceOnPool));
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.cDai.address, supplier1.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.cDai.address, supplier2.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.cDai.address, supplier3.getAddress())).onPool).to.be.lte(1);
    });
  });

  describe('Test liquidation', () => {
    before(initialize);

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
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const collateralBalanceInScaledBalance = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool;
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
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const collateralBalanceBefore = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool;
      const borrowBalanceBefore = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;

      // Set price oracle
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(priceOracle.address);
      priceOracle.setDirectPrice(config.tokens.dai.address, BigNumber.from('1064182920000000000'));
      priceOracle.setDirectPrice(config.tokens.usdc.address, utils.parseUnits('1'));
      priceOracle.setDirectPrice(config.tokens.wbtc.address, utils.parseUnits('1'));
      priceOracle.setDirectPrice(config.tokens.usdt.address, utils.parseUnits('1'));

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate
      const toRepay = maxToBorrow.div(2);
      await daiToken.connect(liquidator).approve(positionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await positionsManagerForAave.connect(liquidator).liquidate(config.tokens.aDai.address, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
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
      expect(removeDigitsBigNumber(6, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(6, expectedCollateralBalanceAfter)
      );
      expect(removeDigitsBigNumber(2, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool)).to.equal(
        removeDigitsBigNumber(2, expectedBorrowBalanceAfter)
      );
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
      await positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, utils.parseUnits('200'));

      // borrower1 supplies USDC as supply (collateral)
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);

      // borrower2 borrows part of supply of borrower1 -> borrower1 has supply in peer-to-peer and on Aave
      const toBorrow = amount;
      const toSupply = BigNumber.from(10).pow(8);
      await wbtcToken.connect(borrower2).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(borrower2).supply(config.tokens.aWbtc.address, toSupply);
      await positionsManagerForAave.connect(borrower2).borrow(config.tokens.aUsdc.address, toBorrow);

      // borrower1 borrows DAI
      const usdcNormalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const p2pUsdcExchangeRate1 = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aUsdc.address);
      const supplyBalanceOnPool1 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool;
      const supplyBalanceInP2P1 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P;
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool1, usdcNormalizedIncome1);
      const supplyBalanceMorphoInUnderlying = p2pUnitToUnderlying(supplyBalanceInP2P1, p2pUsdcExchangeRate1);
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
      await positionsManagerForAave.connect(borrower1).borrow(config.tokens.aDai.address, maxToBorrow);
      const collateralBalanceOnPoolBefore = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool;
      const collateralBalanceInP2PBefore = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P;
      const borrowBalanceInP2PBefore = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P;
      const borrowBalanceOnPoolBefore = (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool;

      // Set price oracle
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(priceOracle.address);
      priceOracle.setDirectPrice(config.tokens.dai.address, BigNumber.from('1070182920000000000'));
      priceOracle.setDirectPrice(config.tokens.usdc.address, utils.parseUnits('1'));
      priceOracle.setDirectPrice(config.tokens.wbtc.address, utils.parseUnits('1'));
      priceOracle.setDirectPrice(config.tokens.usdt.address, utils.parseUnits('1'));

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // liquidator liquidates borrower1's position
      const toRepay = maxToBorrow.mul(LIQUIDATION_CLOSE_FACTOR_PERCENT).div(10000);
      await daiToken.connect(liquidator).approve(positionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await positionsManagerForAave.connect(liquidator).liquidate(config.tokens.aDai.address, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const p2pDaiExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aDai.address);
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
      const expectedCollateralBalanceInP2PAfter = collateralBalanceInP2PBefore.sub(amountToSeize.sub(scaledBalanceToUnderlying(collateralBalanceOnPoolBefore, usdcNormalizedIncome)));
      const expectedBorrowBalanceInP2PAfter = borrowBalanceInP2PBefore.sub(underlyingToP2PUnit(toRepay, p2pDaiExchangeRate));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check liquidatee balances
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(removeDigitsBigNumber(2, (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(2, expectedCollateralBalanceInP2PAfter)
      );
      expect((await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(removeDigitsBigNumber(2, (await positionsManagerForAave.borrowBalanceInOf(config.tokens.aDai.address, borrower1.getAddress())).inP2P)).to.equal(
        removeDigitsBigNumber(2, expectedBorrowBalanceInP2PAfter)
      );

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
      const amount = utils.parseUnits('1');
      await marketsManagerForAave.connect(owner).updateCapValue(config.tokens.aDai.address, newCapValue);

      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, utils.parseUnits('3'));
      expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount)).not.to.reverted;
      expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, amount)).not.to.reverted;
      expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, utils.parseUnits('100'))).to.be.reverted;
      expect(positionsManagerForAave.connect(supplier1).supply(config.tokens.aDai.address, 1)).to.be.reverted;
    });
  });
});
