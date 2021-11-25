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
      const variableDebtTokenAbi = require(config.tokens.variableDebtToken.abi);
      aUsdcToken = await ethers.getContractAt(aTokenAbi, config.tokens.aUsdc.address, owner);
      variableDebtUsdcToken = await ethers.getContractAt(variableDebtTokenAbi, config.tokens.variableDebtUsdc.address, owner);
      aDaiToken = await ethers.getContractAt(aTokenAbi, config.tokens.aDai.address, owner);
      variableDebtDaiToken = await ethers.getContractAt(variableDebtTokenAbi, config.tokens.variableDebtDai.address, owner);
      aUsdtToken = await ethers.getContractAt(aTokenAbi, config.tokens.aUsdt.address, owner);
      variableDebtUsdtToken = await ethers.getContractAt(variableDebtTokenAbi, config.tokens.variableDebtUsdt.address, owner);
      aWbtcToken = await ethers.getContractAt(aTokenAbi, config.tokens.aWbtc.address, owner);
      variableDebtWbtcToken = await ethers.getContractAt(variableDebtTokenAbi, config.tokens.variableDebtWbtc.address, owner);

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

  describe('Worst case scenario for NMAX estimation', () => {
    it('Create scenario', async () => {
      const NMAX = 100;

      /* ###################
       *
       *       BEFORE
       *
       *  ################### */

      let smallDaiBorrowers = [];
      let smallDaiSuppliers = [];
      const whaleDai = await ethers.getSigner(config.tokens.dai.whale);
      const whaleUsdc = await ethers.getSigner(config.tokens.usdc.whale);

      const usdcAmount = to6Decimals(utils.parseUnits('100'));
      const daiAmount = utils.parseUnits('1000');

      // console.log(ethers.Wallet.createRandom());

      for (let i = 0; i < NMAX; i++) {
        // smallDaiSuppliers.push(utils.solidityKeccak256(['uint256'], [i]).slice(0, 42));
        smallDaiSuppliers.push(ethers.Wallet.createRandom().address);

        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallDaiSuppliers[i]],
        });

        const supplier = await ethers.getSigner(smallDaiSuppliers[i]);

        await hre.network.provider.send('hardhat_setBalance', [smallDaiSuppliers[i], utils.hexValue(utils.parseUnits('1000'))]);
        await daiToken.connect(whaleDai).transfer(smallDaiSuppliers[i], daiAmount);

        await daiToken.connect(supplier).approve(positionsManagerForAave.address, daiAmount);
        await positionsManagerForAave.connect(supplier).supply(config.tokens.aDai.address, daiAmount);
      }

      for (let i = NMAX; i < 2 * NMAX; i++) {
        // smallDaiBorrowers.push(utils.solidityKeccak256(['uint256'], [i]).slice(0, 42));
        smallDaiBorrowers.push(ethers.Wallet.createRandom().address);
        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallDaiBorrowers[i]],
        });

        const borrower = await ethers.getSigner(smallDaiBorrowers[i]);

        await hre.network.provider.send('hardhat_setBalance', [smallDaiBorrowers[i], utils.hexValue(utils.parseUnits('1000'))]);
        await usdcToken.connect(whaleUsdc).transfer(smallDaiBorrowers[i], usdcAmount);

        await usdcToken.connect(borrower).approve(positionsManagerForAave.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).supply(config.tokens.aUsdc.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).borrow(config.tokens.aDai.address, daiAmount);
      }

      /* ###################
       *
       *       MATCH
       *
       *  ################### */

      for (let i = 2 * NMAX; i < 3 * NMAX; i++) {
        smallDaiBorrowers.push(ethers.Wallet.createRandom().address);
        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [smallDaiBorrowers[i]],
        });

        const borrower = await ethers.getSigner(smallDaiBorrowers[i]);

        await hre.network.provider.send('hardhat_setBalance', [smallDaiBorrowers[i], utils.hexValue(utils.parseUnits('1000'))]);
        await usdcToken.connect(whaleUsdc).transfer(smallDaiBorrowers[i], usdcAmount);

        await usdcToken.connect(borrower).approve(positionsManagerForAave.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).supply(config.tokens.aUsdc.address, usdcAmount);
        await positionsManagerForAave.connect(borrower).borrow(config.tokens.aDai.address, daiAmount);
      }

      /* ###################
       *
       *       WITHDRAW
       *
       *  ################### */
      expect(marketsManagerForAave.connect(owner).createMarket(config.tokens.usdt.address, utils.parseUnits('1'))).to.be.reverted;
    });
  });
});
