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
  mineBlocks,
} = require('./utils/helpers');


describe('MorphoPositionsManagerForCream Contract', () => {
  let cUsdcToken;
  let cDaiToken;
  let cUsdtToken;
  let cLinkToken;
  let daiToken;
  let usdtToken;
  let uniToken;
  let morphoPositionsManagerForCream;
  let pureSupplierForCream;

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
    snapshotId = await hre.network.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await hre.network.provider.send('evm_revert', [snapshotId]);
  });

  before(async () => {
    // Users
    signers = await ethers.getSigners();
    [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
    suppliers = [supplier1, supplier2, supplier3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy contracts
    const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
    const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
    await redBlackBinaryTree.deployed();

    MorphoMarketsManagerForCompLike = await ethers.getContractFactory('MorphoMarketsManagerForCompLike');
    morphoMarketsManagerForCompLike = await MorphoMarketsManagerForCompLike.deploy();
    await morphoMarketsManagerForCompLike.deployed();

    MorphoPositionsManagerForCream = await ethers.getContractFactory('MorphoPositionsManagerForCream', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    morphoPositionsManagerForCream = await MorphoPositionsManagerForCream.deploy(morphoMarketsManagerForCompLike.address, config.cream.comptroller.address);
    await morphoPositionsManagerForCream.deployed();

    pureSupplierForCream = await ethers.getContractFactory('PureSupplierForCream');
    pureSupplierForCream = await pureSupplierForCream.deploy(morphoPositionsManagerForCream.address);
    await pureSupplierForCream.deployed();

    // Get contract dependencies
    const cTokenAbi = require(config.tokens.cToken.abi);
    cUsdcToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdc.address, owner);
    cDaiToken = await ethers.getContractAt(cTokenAbi, config.tokens.cDai.address, owner);
    cUsdtToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdt.address, owner);
    cUniToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUni.address, owner);
    cLinkToken = await ethers.getContractAt(cTokenAbi, config.tokens.cLink.address, owner);

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

  describe('Deployment', () => {
    it('Should deploy the contract with the right values', async () => {
      expect(await pureSupplierForCream.marketsManager()).to.equal(morphoMarketsManagerForCompLike.address);
      expect(await pureSupplierForCream.positionsManager()).to.equal(morphoPositionsManagerForCream.address);
    });
  });

  describe('Depositors', () => {
    it('Users should be able to deposit tokens', async () => {
      const amount1 = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(supplier1).approve(pureSupplierForCream.address, amount1);
      await pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount1);

      const deposited = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureSupplierForCream.address)).onCream;
      const exchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const expectedSupplyBalanceOnCream = underlyingToCToken(amount1, exchangeRate);

      expect(deposited).to.equal(expectedSupplyBalanceOnCream);
    });

    it('User should be able to withdraw deposited amount and interest accrued on Cream', async () => {
      // Supplier1 supplies 10000 tokens
      const amount = to6Decimals(utils.parseUnits('10000'));
      await usdcToken.connect(supplier1).approve(pureSupplierForCream.address, amount);
      await pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount);
      const originalBalance = await usdcToken.balanceOf(supplier1.address);

      mineBlocks(1000);

      const suppliedOnCream = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureSupplierForCream.address)).onCream;

      // Update Exchange Rate
      await morphoMarketsManagerForCompLike.updateBPY(config.tokens.cUsdc.address);
      const currentExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();

      // Supplier1 withdraws all her tokens
      const shares = await pureSupplierForCream.shares(config.tokens.cUsdc.address, supplier1.address);
      await pureSupplierForCream.connect(supplier1).withdraw(config.tokens.cUsdc.address, shares);
      const supplier1Balance = await usdcToken.balanceOf(supplier1.address);

      // Shouldn't be liquidity left on PureSupplier
      const remaining = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureSupplierForCream.address)).onCream;

      expect(remaining).to.be.below(1e5);
      expect(supplier1Balance).to.be.above(originalBalance);
    });

    it('Values should be equal to the interest collected', async () => {
      // Supplier1's balance before supplying any tokens
      const balanceBefore = await usdcToken.balanceOf(supplier1.address);

      // Initialize Exchange rate
      await morphoMarketsManagerForCompLike.updateBPY(config.tokens.cUsdc.address);

      // Supplier1 supplies 50 tokens
      const amount = to6Decimals(utils.parseUnits('50'));
      await usdcToken.connect(supplier1).approve(pureSupplierForCream.address, amount);
      await pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount);

      const suppliedOnCream = (await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureSupplierForCream.address)).onCream;

      mineBlocks(10000);

      // First Exchange Rate
      await morphoMarketsManagerForCompLike.updateBPY(config.tokens.cUsdc.address);
      const exchangeRate1 = await cUsdcToken.callStatic.exchangeRateCurrent();

      // Supplier1 supplies again 50 tokens
      await usdcToken.connect(supplier1).approve(pureSupplierForCream.address, amount);
      await pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount);

      mineBlocks(10000);

      // Second Exchange Rate
      await morphoMarketsManagerForCompLike.updateBPY(config.tokens.cUsdc.address);
      const exchangeRate2 = await cUsdcToken.callStatic.exchangeRateCurrent();

      // Compute exptected Balance
      const expectedSharesValueInUnderlying = cTokenToUnderlying(suppliedOnCream, exchangeRate1).add(cTokenToUnderlying(suppliedOnCream, exchangeRate2));

      // Supplier1 withdraws all her tokens
      const shares = await pureSupplierForCream.shares(config.tokens.cUsdc.address, supplier1.address);
      await pureSupplierForCream.connect(supplier1).withdraw(config.tokens.cUsdc.address, shares);
      const balanceAfter = await usdcToken.balanceOf(supplier1.address);

      expect(expectedSharesValueInUnderlying - (balanceAfter - balanceBefore + 2 * amount)).to.be.below(50);
    });

    it('Share value should be equal to deposited amount at the beginning', async () => {
      // Supplier1 supplies 50 tokens
      const amount1 = to6Decimals(utils.parseUnits('50'));
      await usdcToken.connect(supplier1).approve(pureSupplierForCream.address, amount1);
      await pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount1);

      // Supplier2 supplies 200 tokens
      const amount2 = to6Decimals(utils.parseUnits('200'));
      await usdcToken.connect(supplier2).approve(pureSupplierForCream.address, amount2);
      await pureSupplierForCream.connect(supplier2).supply(config.tokens.cUsdc.address, amount2);

      // Supplier1 re-supplies 100 tokens
      const amount3 = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(supplier1).approve(pureSupplierForCream.address, amount3);
      await pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount3);

      const shares1 = (await pureSupplierForCream.shares(config.tokens.cUsdc.address, supplier1.address)).toNumber();
      const shares2 = (await pureSupplierForCream.shares(config.tokens.cUsdc.address, supplier2.address)).toNumber();

      const nbOfShares = shares1 + shares2;
      const totalDeposited = amount1.toNumber() + amount2.toNumber() + amount3.toNumber();

      const valueSupplier1 = (totalDeposited / nbOfShares) * shares1;
      const depositedSupplier1 = amount1.toNumber() + amount3.toNumber();

      const valueSupplier2 = (totalDeposited / nbOfShares) * shares2;
      const depositedSupplier2 = amount2.toNumber();

      expect(valueSupplier1 - depositedSupplier1).to.be.below(1);
      expect(valueSupplier2 - depositedSupplier2).to.be.below(1);
    });
  });

  describe('Basic operations', () => {
    it('User should not be able to deposit with zero funds', async () => {
      await expect(pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, 0)).to.be.reverted;
    });

    it('User should not be able to deposit on non created market', async () => {
      linkToken = await getTokens('0x5ca6ca6c3709e1e6cfe74a50cf6b2b6ba2dadd67', 'whale', signers, config.tokens.link, utils.parseUnits('10'));

      const amount = utils.parseUnits('10');
      await linkToken.connect(supplier1).approve(pureSupplierForCream.address, amount);
      await expect(pureSupplierForCream.connect(supplier1).supply(config.tokens.cLink.address, amount)).to.be.reverted;
    });

    it('User should deposit and withdraw all', async () => {
      const balanceBefore = await usdcToken.balanceOf(supplier1.address);

      // Supply
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(supplier1).approve(pureSupplierForCream.address, amount);
      await pureSupplierForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount);
      // PureSupplier has tokens on PositionsManager
      const supplyBalanceOnMorpho = await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureSupplierForCream.address);
      const rate = await cUsdcToken.callStatic.exchangeRateCurrent();
      expect(supplyBalanceOnMorpho.onCream).to.equal(underlyingToCToken(amount, rate));
      // Sender has shares on PureSupplier
      const shares = await pureSupplierForCream.shares(config.tokens.cUsdc.address, supplier1.address);
      expect(shares).to.equal(amount);

      // Withdraw
      await pureSupplierForCream.connect(supplier1).withdraw(config.tokens.cUsdc.address, shares);
      // PositionsManager no longer has tokens
      const supplyBalanceOnMorphoAfter = await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureSupplierForCream.address);
      expect(supplyBalanceOnMorphoAfter.onCream).to.be.lte(1000); // Dust
      expect(supplyBalanceOnMorphoAfter.inP2P).to.equal(0);
      // Sender no longer has shares
      expect(await pureSupplierForCream.shares(config.tokens.cUsdc.address, supplier1.address)).to.equal(0);
      // Sender has tokens
      expect(await usdcToken.balanceOf(supplier1.address)).to.equal(balanceBefore);
    });
  });

});
