import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { to6Decimals, getTokens } from './utils/common-helpers';
import { WAD } from './utils/compound-helpers';

describe('PositionsManagerForCompound Contract', () => {
  // Tokens
  let daiToken: Contract;
  let uniToken: Contract;
  let usdcToken: Contract;

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

  const Bob = '0xc03004e3ce0784bf68186394306849f9b7b12000';

  const initialize = async () => {
    // Signers
    signers = await ethers.getSigners();
    [owner, liquidator] = signers;

    // Deploy RedBlackBinaryTree
    const RedBlackBinaryTree = await ethers.getContractFactory('contracts/compound/libraries/RedBlackBinaryTree.sol:RedBlackBinaryTree');
    const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
    await redBlackBinaryTree.deployed();

    // Deploy UpdatePositions
    const UpdatePositions = await ethers.getContractFactory('contracts/compound/UpdatePositions.sol:UpdatePositions', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    const updatePositions = await UpdatePositions.deploy();
    await updatePositions.deployed();

    // Deploy MarketsManagerForCompound
    const MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
    marketsManagerForCompound = await MarketsManagerForCompound.deploy();
    await marketsManagerForCompound.deployed();

    // Deploy PositionsManagerForCompound
    const PositionsManagerForCompound = await ethers.getContractFactory('PositionsManagerForCompound', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    positionsManagerForCompound = await PositionsManagerForCompound.deploy(
      marketsManagerForCompound.address,
      config.compound.comptroller.address,
      updatePositions.address
    );
    fakeCompoundPositionsManager = await PositionsManagerForCompound.deploy(
      marketsManagerForCompound.address,
      config.compound.comptroller.address,
      updatePositions.address
    );
    await positionsManagerForCompound.deployed();
    await fakeCompoundPositionsManager.deployed();

    // Get contract dependencies
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

      // They also borrow Uni so they are matched with Bob's collateral
      const UniPriceMantissa = await compoundOracle.getUnderlyingPrice(config.tokens.cUni.address);
      const { collateralFactorMantissa } = await comptroller.markets(config.tokens.cDai.address);
      const maxToBorrow = daiAmount.div(UniPriceMantissa).mul(collateralFactorMantissa);

      await positionsManagerForCompound.connect(supplier).borrow(config.tokens.cUni.address, maxToBorrow);
    }
  };

  describe('Worst case scenario for NMAX estimation', () => {
    const NMAX = 25;
    const daiAmountBob = utils.parseUnits('5000'); // 2*NMAX*SuppliedPerUser

    it('Set new NMAX', async () => {
      expect(await positionsManagerForCompound.NMAX()).to.equal(1000);
      await marketsManagerForCompound.connect(owner).setMaxNumberOfUsersInTree(NMAX);
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

    // Now comes Bob, he supplies UNI and his collateral is matched with the NMAX 'Tree Dai Supplier' that are borrowing it.
    // Bob also borrows a large quantity of DAI, so that his dai comes from the NMAX 'Tree Dai Supplier'
    it('Add Bob', async () => {
      const whaleUni = await ethers.getSigner(config.tokens.uni.whale);

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [Bob],
      });

      const bobSigner = await ethers.getSigner(Bob);

      await hre.network.provider.send('hardhat_setBalance', [Bob, utils.hexValue(utils.parseUnits('1000'))]);
      await uniToken.connect(whaleUni).transfer(Bob, daiAmountBob.mul(100));

      await uniToken.connect(bobSigner).approve(positionsManagerForCompound.address, daiAmountBob.mul(100));
      await positionsManagerForCompound.connect(bobSigner).supply(config.tokens.cUni.address, daiAmountBob.mul(100));
      await positionsManagerForCompound.connect(bobSigner).borrow(config.tokens.cDai.address, daiAmountBob);
    });

    // Now Bob decides to leave Morpho, so he proceeds to a repay and a withdraw of his funds.
    it('Bob leaves', async () => {
      const bobSigner = await ethers.getSigner(Bob);
      console.log(await positionsManagerForCompound.borrowBalanceInOf(config.tokens.cDai.address, Bob));
      console.log(await positionsManagerForCompound.supplyBalanceInOf(config.tokens.cUni.address, Bob));

      await daiToken.connect(bobSigner).approve(positionsManagerForCompound.address, daiAmountBob.mul(4));
      await positionsManagerForCompound.connect(bobSigner).repay(config.tokens.cDai.address, daiAmountBob);
      await positionsManagerForCompound.connect(bobSigner).withdraw(config.tokens.cUni.address, utils.parseUnits('19900'));
    });

    xit('Bob gets liquidated', async () => {
      const PriceOracle = await ethers.getContractFactory('contracts/compound/test/SimplePriceOracle.sol:SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install Admin
      const adminAddress = await comptroller.admin();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      // Set Uni price to 0
      await comptroller.connect(admin)._setPriceOracle(priceOracle.address);
      priceOracle.setUnderlyingPrice(config.tokens.cDai.address, BigNumber.from('100000000000000000000000'));

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      await daiToken.connect(liquidator).approve(positionsManagerForCompound.address, daiAmountBob);
      console.log('1');
      await positionsManagerForCompound
        .connect(liquidator)
        .liquidate(config.tokens.cDai.address, config.tokens.cUni.address, Bob, daiAmountBob);
      console.log('2');
    });

    xit('Bob gets liquidated', async () => {
      const PriceOracle = await ethers.getContractFactory('contracts/compound/test/SimplePriceOracle.sol:SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install Admin
      const adminAddress = await comptroller.admin();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      // Set Uni price to 0
      await comptroller.connect(admin)._setPriceOracle(priceOracle.address);
      priceOracle.setUnderlyingPrice(config.tokens.cUni.address, BigNumber.from('1000000000000000000000000000000'));

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Bob gets liquidated
      const closeFactor = await comptroller.closeFactorMantissa();
      const toRepay = daiAmountBob.mul(closeFactor).div(WAD);

      await daiToken.connect(liquidator).approve(positionsManagerForCompound.address, toRepay);
      console.log('1');
      await positionsManagerForCompound.connect(liquidator).liquidate(config.tokens.cDai.address, config.tokens.cUni.address, Bob, toRepay);
      console.log('2');
    });
  });
});
