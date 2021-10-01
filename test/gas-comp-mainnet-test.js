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

    const ethAmount = utils.parseUnits('100');

    // Mint some ERC20
    // Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
    const daiMinter = '0x9759A6Ac90977b93B58547b4A71c78317f391A28';
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [daiMinter],
    });
    const daiSigner = await ethers.getSigner(daiMinter);
    daiToken = await ethers.getContractAt(require(config.tokens.dai.abi), config.tokens.dai.address, daiSigner);
    const daiAmount = utils.parseUnits('100000000');
    await hre.network.provider.send('hardhat_setBalance', [daiMinter, utils.hexValue(ethAmount)]);

    // Mint DAI to all lenders and borrowers
    await Promise.all(
      signers.map(async (signer) => {
        await daiToken.mint(signer.getAddress(), daiAmount, {
          from: daiMinter,
        });
      })
    );

    const usdcMinter = '0x5b6122c109b78c6755486966148c1d70a50a47d7';
    // const masterMinter = await usdcToken.masterMinter();
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [usdcMinter],
    });
    const usdcSigner = await ethers.getSigner(usdcMinter);
    usdcToken = await ethers.getContractAt(require(config.tokens.usdc.abi), config.tokens.usdc.address, usdcSigner);
    const usdcAmount = BigNumber.from(10).pow(10); // 10 000 USDC
    await hre.network.provider.send('hardhat_setBalance', [usdcMinter, utils.hexValue(ethAmount)]);

    // Mint USDC
    await Promise.all(
      signers.map(async (signer) => {
        await usdcToken.mint(signer.getAddress(), usdcAmount, {
          from: usdcMinter,
        });
      })
    );

    const usdtWhale = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [usdtWhale],
    });
    const usdtWhaleSigner = await ethers.getSigner(usdtWhale);
    usdcToken = await ethers.getContractAt(require(config.tokens.usdc.abi), config.tokens.usdc.address, usdtWhaleSigner);
    const usdtAmount = BigNumber.from(10).pow(10); // 10 000 USDT
    await hre.network.provider.send('hardhat_setBalance', [usdtWhale, utils.hexValue(ethAmount)]);

    // Transfer USDT
    await Promise.all(
      signers.map(async (signer) => {
        await usdtToken.connect(usdtWhaleSigner).transfer(signer.getAddress(), usdtAmount);
      })
    );

    // Mint UNI
    const uniMinter = '0x1a9c8182c09f50c8318d769245bea52c32be35bc';
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [uniMinter],
    });
    const uniSigner = await ethers.getSigner(uniMinter);
    uniToken = await ethers.getContractAt(require(config.tokens.uni.abi), config.tokens.uni.address, uniSigner);
    const uniAmount = utils.parseUnits('10000'); // 10 000 UNI
    await hre.network.provider.send('hardhat_setBalance', [uniMinter, utils.hexValue(ethAmount)]);

    // Transfer UNI
    await Promise.all(
      signers.map(async (signer) => {
        await uniToken.connect(uniSigner).transfer(signer.getAddress(), uniAmount);
      })
    );

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
});
