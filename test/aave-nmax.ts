/* eslint-disable no-console */
import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers, upgrades } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { MAX_INT, to6Decimals, getTokens } from './utils/common-helpers';
import { WAD, PERCENT_BASE, scaledBalanceToUnderlying } from './utils/aave-helpers';

describe('PositionsManagerForAave Contract', () => {
  // Tokens
  let daiToken: Contract;
  let usdcToken: Contract;
  let wbtcToken: Contract;

  // Contracts
  let positionsManagerForAave: Contract;
  let marketsManagerForAave: Contract;
  let lendingPoolAddressesProvider: Contract;
  let lendingPool: Contract;
  let protocolDataProvider: Contract;
  let oracle: Contract;

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

    // Deploy MarketsManagerForAave
    const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
    marketsManagerForAave = await MarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
    await marketsManagerForAave.deployed();

    // Get PositionsManager address
    positionsManagerForAave = await ethers.getContractAt('PositionsManagerForAave', await marketsManagerForAave.positionsManager());

    // Deploy PositionsUpdator
    const PositionsUpdator = await ethers.getContractFactory('PositionsUpdatorV1');
    const positionsUpdatorProxy = await upgrades.deployProxy(PositionsUpdator, [positionsManagerForAave.address], {
      kind: 'uups',
      unsafeAllow: ['delegatecall'],
    });
    await positionsUpdatorProxy.deployed();

    // Set proxy
    await marketsManagerForAave.updatePositionsUpdator(positionsUpdatorProxy.address);
    await marketsManagerForAave.updateMaxIterations(20);

    // Get contract dependencies
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

    // Create and list markets
    await marketsManagerForAave.connect(owner).updateLendingPool();
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, WAD, MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address, BigNumber.from(10).pow(4), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address, WAD, MAX_INT);
  };

  before(initialize);

  const addSmallDaiBorrowers = async (maxIterations: number) => {
    {
      const whaleUsdc = await ethers.getSigner(config.tokens.usdc.whale);
      const daiAmount = utils.parseUnits('80');
      const usdcAmount = to6Decimals(utils.parseUnits('1000'));
      let smallDaiBorrower;

      for (let i = 0; i < maxIterations; i++) {
        console.log('addSmallDaiBorrowers', i);

        smallDaiBorrower = ethers.Wallet.createRandom().address;

        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallDaiBorrower],
        });

        const borrower = await ethers.getSigner(smallDaiBorrower);

        await hre.network.provider.send('hardhat_setBalance', [smallDaiBorrower, utils.hexValue(utils.parseUnits('1000'))]);
        await usdcToken.connect(whaleUsdc).transfer(smallDaiBorrower, usdcAmount);

        await usdcToken.connect(borrower).approve(positionsManagerForAave.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).supply(config.tokens.aUsdc.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).borrow(config.tokens.aDai.address, daiAmount);
      }
    }
  };

  const addSmallDaiSuppliers = async (maxIterations: number) => {
    const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
    const daiAmount = utils.parseUnits('80');
    let smallDaiSupplier;

    for (let i = 0; i < maxIterations; i++) {
      console.log('addSmallDaiSuppliers', i);

      smallDaiSupplier = ethers.Wallet.createRandom().address;
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [smallDaiSupplier],
      });

      const supplier = await ethers.getSigner(smallDaiSupplier);
      await hre.network.provider.send('hardhat_setBalance', [smallDaiSupplier, utils.hexValue(utils.parseUnits('1000'))]);

      await daiToken.connect(whaleDai).transfer(smallDaiSupplier, daiAmount);
      await daiToken.connect(supplier).approve(positionsManagerForAave.address, daiAmount);
      await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, daiAmount);
    }
  };

  const addTreeDaiSuppliers = async (maxIterations: number) => {
    const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
    const daiAmount = utils.parseUnits('100');
    let treeDaiSupplier;

    for (let i = 0; i < maxIterations; i++) {
      console.log('addTreeDaiSuppliers', i);
      treeDaiSupplier = ethers.Wallet.createRandom().address;

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [treeDaiSupplier],
      });

      const supplier = await ethers.getSigner(treeDaiSupplier);

      await hre.network.provider.send('hardhat_setBalance', [treeDaiSupplier, utils.hexValue(utils.parseUnits('1000'))]);
      await daiToken.connect(whaleDai).transfer(treeDaiSupplier, daiAmount);

      await daiToken.connect(supplier).approve(positionsManagerForAave.address, daiAmount);
      await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, daiAmount);

      // They also borrow Wbtc so they are matched with Alice's collateral
      const collateralBalanceInUnderlying = daiAmount;
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(config.tokens.dai.address);
      const wbtcPrice = await oracle.getAssetPrice(config.tokens.wbtc.address);
      const wbtcDecimals = await wbtcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(config.tokens.dai.address);
      const daiDecimals = await daiToken.decimals();
      const maxToBorrow = collateralBalanceInUnderlying
        .mul(daiPrice)
        .div(BigNumber.from(10).pow(daiDecimals))
        .mul(BigNumber.from(10).pow(wbtcDecimals))
        .div(wbtcPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);

      await positionsManagerForAave.connect(supplier).borrow(config.tokens.aWbtc.address, maxToBorrow);
    }
  };

  describe('Worst case scenario for maxIterations estimation', () => {
    const maxIterations = 20;
    const daiAmountAlice = utils.parseUnits('5000'); // 2*maxIterations*SuppliedPerUser
    const wbtcAmountAlice = to6Decimals(utils.parseUnits('1000'));

    it('Set new maxIterations', async () => {
      expect(await positionsManagerForAave.maxIterations()).to.equal(1000);
      await marketsManagerForAave.connect(owner).updateMaxIterations(maxIterations);
      expect(await positionsManagerForAave.maxIterations()).to.equal(maxIterations);
    });

    // We have some borrowers that are taking some DAI and supplying as collateral USDC
    it('Add small Dai borrowers', async () => {
      await addSmallDaiBorrowers(maxIterations);
    });

    // We have some DAI supplier. They are matched with previous Dai borrowers.
    // We have maxIterations match for the DAI market.
    it('Add small Dai Suppliers', async () => {
      await addSmallDaiSuppliers(maxIterations);
    });

    // Now, comes other DAI Supplier, that are supplying a greater amount.
    // Also, they borrow some Wbtc.
    it('Add Tree Dai Suppliers', async () => {
      await addTreeDaiSuppliers(maxIterations);
    });

    // Now comes alice, she supplies Wbtc and her collateral is matched with the maxIterations 'Tree Dai Supplier' that are borrowing it.
    // alice also borrows a large quantity of DAI, so that her dai comes from the maxIterations 'Tree Dai Supplier'
    it('Add alice', async () => {
      const whaleWbtc = await ethers.getSigner(config.tokens.wbtc.whale);
      await wbtcToken.connect(whaleWbtc).transfer(aliceAddress, wbtcAmountAlice);
      await wbtcToken.connect(alice).approve(positionsManagerForAave.address, wbtcAmountAlice);
      await positionsManagerForAave.connect(alice).supply(config.tokens.aWbtc.address, wbtcAmountAlice);
      await positionsManagerForAave.connect(alice).borrow(config.tokens.aDai.address, daiAmountAlice);
    });

    // Now alice decides to leave Morpho, so she proceeds to a repay and a withdraw of her funds.
    it('alice leaves', async () => {
      await daiToken.connect(alice).approve(positionsManagerForAave.address, daiAmountAlice);
      await positionsManagerForAave.connect(alice).repay(config.tokens.aDai.address, utils.parseUnits('4990'));
      await positionsManagerForAave.connect(alice).withdraw(config.tokens.aWbtc.address, to6Decimals(utils.parseUnits('999')));
    });
  });

  describe('Specific case of liquidation with maxIterations', () => {
    it('Re initialize', async () => {
      await initialize();
    });

    const maxIterations = 20;
    const usdcCollateralAmount = to6Decimals(utils.parseUnits('10000'));
    let daiBorrowAmount: BigNumber;
    let admin: Signer;

    it('Set new maxIterations', async () => {
      await marketsManagerForAave.connect(owner).updateMaxIterations(maxIterations);
      expect(await positionsManagerForAave.maxIterations()).to.equal(maxIterations);
    });

    it('Setup admin', async () => {
      const adminAddress = await lendingPoolAddressesProvider.owner();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      admin = await ethers.getSigner(adminAddress);
    });

    // First step. alice comes and borrows 'daiBorrowAmount' while putting in collateral 'usdcCollateralAmount'

    // Second step. 2*maxIterations suppliers are going to be matched with her debt.
    // (2*maxIterations because in the liquidation we have a max liquidation of 50%)

    // Third step. 2*maxIterations borrowers comes and are match with the collateral.

    // Fourth step. There is a price variation.

    // Fifth step. 50% of Alice's position is liquidated, thus generating maxIterations unmatch of suppliers and borrowers.

    it('First step, alice comes', async () => {
      const whaleUsdc = await ethers.getSigner(config.tokens.usdc.whale);
      await usdcToken.connect(whaleUsdc).transfer(aliceAddress, usdcCollateralAmount);

      await usdcToken.connect(alice).approve(positionsManagerForAave.address, usdcCollateralAmount);
      await positionsManagerForAave.connect(alice).supply(config.tokens.aUsdc.address, usdcCollateralAmount);

      const collateralBalanceInScaledBalance = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, aliceAddress))
        .onPool;
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInUnderlying = scaledBalanceToUnderlying(collateralBalanceInScaledBalance, normalizedIncome);
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(config.tokens.dai.address);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.usdc.address);
      const usdcDecimals = await usdcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(config.tokens.dai.address);
      const daiDecimals = await daiToken.decimals();
      daiBorrowAmount = collateralBalanceInUnderlying
        .mul(usdcPrice)
        .div(BigNumber.from(10).pow(usdcDecimals))
        .mul(BigNumber.from(10).pow(daiDecimals))
        .div(daiPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);

      await positionsManagerForAave.connect(alice).borrow(config.tokens.aDai.address, daiBorrowAmount);
    });

    it('Second step, add 2*maxIterations Dai suppliers', async () => {
      const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
      const daiAmount = daiBorrowAmount.div(2 * maxIterations);
      let smallDaiSupplier;

      for (let i = 0; i < 2 * maxIterations; i++) {
        console.log('add Dai Suppliers', i);

        smallDaiSupplier = ethers.Wallet.createRandom().address;
        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallDaiSupplier],
        });

        const supplier = await ethers.getSigner(smallDaiSupplier);
        await hre.network.provider.send('hardhat_setBalance', [smallDaiSupplier, utils.hexValue(utils.parseUnits('1000'))]);

        await daiToken.connect(whaleDai).transfer(smallDaiSupplier, daiAmount);
        await daiToken.connect(supplier).approve(positionsManagerForAave.address, daiAmount);
        await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, daiAmount);
      }
    });

    it('third step, add 2*maxIterations Usdc borrowers', async () => {
      const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
      const usdcAmount = usdcCollateralAmount.div(2 * maxIterations);
      const daiAmount = utils.parseUnits(usdcAmount.mul(2).div(1e6).toString());
      let smallUsdcBorrower;

      for (let i = 0; i < 2 * maxIterations; i++) {
        console.log('addsmallUsdcBorrowers', i);

        smallUsdcBorrower = ethers.Wallet.createRandom().address;

        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallUsdcBorrower],
        });

        const borrower = await ethers.getSigner(smallUsdcBorrower);

        await hre.network.provider.send('hardhat_setBalance', [smallUsdcBorrower, utils.hexValue(utils.parseUnits('1000'))]);
        await daiToken.connect(whaleDai).transfer(smallUsdcBorrower, daiAmount);

        await daiToken.connect(borrower).approve(positionsManagerForAave.address, daiAmount);
        await positionsManagerForAave.connect(borrower).supply(config.tokens.aDai.address, daiAmount);
        await positionsManagerForAave.connect(borrower).borrow(config.tokens.aUsdc.address, usdcAmount);
      }
    });

    it('Fourth & fifth steps, price variation & liquidation', async () => {
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('contracts/aave/test/SimplePriceOracle.sol:SimplePriceOracle');
      const priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(priceOracle.address);
      priceOracle.setDirectPrice(config.tokens.dai.address, WAD.mul(110).div(100));
      priceOracle.setDirectPrice(config.tokens.usdc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.wbtc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.usdt.address, WAD);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate alice
      const toRepay = daiBorrowAmount.div(2);

      await daiToken.connect(liquidator).approve(positionsManagerForAave.address, toRepay);
      await positionsManagerForAave
        .connect(liquidator)
        .liquidate(config.tokens.aDai.address, config.tokens.aUsdc.address, aliceAddress, toRepay);
    });
  });
});
