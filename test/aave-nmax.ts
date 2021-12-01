import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { MAX_INT, to6Decimals, getTokens } from './utils/common-helpers';
import { WAD } from './utils/aave-helpers';

describe('PositionsManagerForAave Contract', () => {
  const PERCENT_BASE: BigNumber = BigNumber.from(10000);

  // Tokens
  let daiToken: Contract;
  let usdcToken: Contract;
  let wbtcToken: Contract;

  // Contracts
  let positionsManagerForAave: Contract;
  let marketsManagerForAave: Contract;
  let fakeAavePositionsManager: Contract;
  let lendingPoolAddressesProvider: Contract;
  let protocolDataProvider: Contract;
  let oracle: Contract;

  // Signers
  let signers: Signer[];
  let owner: Signer;

  const Bob = '0xc03004e3ce0784bf68186394306849f9b7b12000';

  const initialize = async () => {
    // Signers
    signers = await ethers.getSigners();
    [owner] = signers;

    // Deploy RedBlackBinaryTree
    const RedBlackBinaryTree = await ethers.getContractFactory('contracts/aave/libraries/RedBlackBinaryTree.sol:RedBlackBinaryTree');
    const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
    await redBlackBinaryTree.deployed();

    // Deploy UpdatePositions
    const UpdatePositions = await ethers.getContractFactory('contracts/aave/UpdatePositions.sol:UpdatePositions', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    const updatePositions = await UpdatePositions.deploy();
    await updatePositions.deployed();

    // Deploy MarketsManagerForAave
    const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
    marketsManagerForAave = await MarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
    await marketsManagerForAave.deployed();

    // Deploy PositionsManagerForAave
    const PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    positionsManagerForAave = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address,
      updatePositions.address
    );
    fakeAavePositionsManager = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address,
      updatePositions.address
    );
    await positionsManagerForAave.deployed();
    await fakeAavePositionsManager.deployed();

    // Get contract dependencies
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
    await marketsManagerForAave.connect(owner).setPositionsManager(positionsManagerForAave.address);
    await marketsManagerForAave.connect(owner).setLendingPool();
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, WAD, MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address, BigNumber.from(10).pow(4), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address, to6Decimals(WAD), MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address, WAD, MAX_INT);
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

        await usdcToken.connect(borrower).approve(positionsManagerForAave.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).supply(config.tokens.aUsdc.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).borrow(config.tokens.aDai.address, daiAmount);
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
      await daiToken.connect(supplier).approve(positionsManagerForAave.address, daiAmount);
      await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, daiAmount);
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

      await daiToken.connect(supplier).approve(positionsManagerForAave.address, daiAmount);
      await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, daiAmount);

      // They also borrow Wbtc so they are matched with Bob's collateral
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

  describe('Worst case scenario for NMAX estimation', () => {
    const NMAX = 25;
    const daiAmountBob = utils.parseUnits('5000');
    const wbtcAmountBob = to6Decimals(utils.parseUnits('1000'));

    it('Set new NMAX', async () => {
      expect(await positionsManagerForAave.NMAX()).to.equal(1000);
      await marketsManagerForAave.connect(owner).setMaxNumberOfUsersInTree(NMAX);
      expect(await positionsManagerForAave.NMAX()).to.equal(NMAX);
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
    // Also, they borrow some Wbtc.
    it('Add Tree Dai Suppliers', async () => {
      await addTreeDaiSuppliers(NMAX);
    });

    // Now comes Bob, he supplies Wbtc and his collateral is matched with the NMAX 'Tree Dai Supplier' that are borrowing it.
    // Bob also borrows a large quantity of DAI, so that his dai comes from the NMAX 'Tree Dai Supplier'
    it('Add Bob', async () => {
      const whaleWbtc = await ethers.getSigner(config.tokens.wbtc.whale);

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [Bob],
      });

      const bobSigner = await ethers.getSigner(Bob);

      await hre.network.provider.send('hardhat_setBalance', [Bob, utils.hexValue(utils.parseUnits('1000'))]);
      await wbtcToken.connect(whaleWbtc).transfer(Bob, wbtcAmountBob);
      await wbtcToken.connect(bobSigner).approve(positionsManagerForAave.address, wbtcAmountBob);
      await positionsManagerForAave.connect(bobSigner).supply(config.tokens.aWbtc.address, wbtcAmountBob);
      await positionsManagerForAave.connect(bobSigner).borrow(config.tokens.aDai.address, daiAmountBob);
    });

    // Now Bob decides to leave Morpho, so he proceeds to a repay and a withdraw of his funds.
    it('Bob leaves', async () => {
      const bobSigner = await ethers.getSigner(Bob);
      await daiToken.connect(bobSigner).approve(positionsManagerForAave.address, daiAmountBob);
      await positionsManagerForAave.connect(bobSigner).repay(config.tokens.aDai.address, daiAmountBob);
      await positionsManagerForAave.connect(bobSigner).withdraw(config.tokens.aWbtc.address, wbtcAmountBob);
    });
  });
});
