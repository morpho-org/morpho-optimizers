const { expect } = require("chai");
const hre = require("hardhat");
const { utils, BigNumber } = require('ethers');
// Use mainnet ABIs
const daiAbi = require('./abis/daiABI.json');
const CErc20ABI = require('./abis/CErc20ABI.json');
const CEthABI = require('./abis/CEthABI.json');

describe("CompoundModuleETH Contract", () => {

  const WETH_ADDRESS = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";
  const CETH_ADDRESS = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
  const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const CDAI_ADDRESS = "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643";
  const COMPOUND_ORACLE_ADDRESS = "0x841616a5CBA946CF415Efe8a326A621A794D0f97";

  const cTokenDecimals = 8; // all cTokens have 8 decimal places

  let cEthToken;
  let cDaiToken;
  let daiToken;
  let CompoundModule;
  let compoundModule;

  let owner;
  let lender;
  let borrower;
  let addrs;

  const underlyingToCToken = (underlyingAmount, exchangeRateCurrent) => {
    return BigNumber.from(underlyingAmount).mul(BigNumber.from(10).pow(18)).div(BigNumber.from(exchangeRateCurrent));
  }

  const cTokenToUnderlying = (cTokenAmount, exchangeRateCurrent) => {
    return BigNumber.from(cTokenAmount).mul(BigNumber.from(exchangeRateCurrent)).div(BigNumber.from(10).pow(18));
  }

  beforeEach(async () => {
    // CompoundModule
    CompoundModule = await ethers.getContractFactory("CompoundModuleETH");
    [lender, borrower, owner, ...addrs] = await ethers.getSigners();
    compoundModule = await CompoundModule.deploy();
    await compoundModule.deployed();

    cEthToken = await ethers.getContractAt(CEthABI, CETH_ADDRESS, lender);
    cDaiToken = await ethers.getContractAt(CErc20ABI, CDAI_ADDRESS, lender);
    const daiMinter = '0x9759A6Ac90977b93B58547b4A71c78317f391A28';
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [daiMinter],
    });
    const daiSigner = await ethers.getSigner(daiMinter);
    daiToken = await ethers.getContractAt(daiAbi, DAI_ADDRESS, daiSigner);

    // Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
    const daiAmount = utils.parseUnits("10000");
    const ethAmount = utils.parseUnits("100");
    await network.provider.send("hardhat_setBalance", [
      daiMinter,
      utils.hexValue(ethAmount),
    ]);
    await daiToken.mint(lender.getAddress(), daiAmount, { from: daiMinter });
  });

  describe("Deployment", () => {
    it("Should deploy the contract", async () => {
      expect(await compoundModule.collateralFactor()).to.equal("750000000000000000");
      expect(await compoundModule.liquidationIncentive()).to.equal("8000");
      expect(await compoundModule.DENOMINATOR()).to.equal("10000");
    });
  });

  describe("Lending when there is no borrowers", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho).to.equal(0);
    })

    it("Should revert when lending 0", async () => {
      await expect(compoundModule.connect(lender).lend(0)).to.be.revertedWith("Amount cannot be 0");
    })

    it("Should have the right amount of cDAI onComp after lending DAI", async () => {
      const amount = utils.parseUnits("10");
      await daiToken.connect(lender).approve(compoundModule.address, amount);
      await compoundModule.connect(lender).lend(amount);
      const exchangeRateCurrent = await cDaiToken.exchangeRateStored();
      const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRateCurrent);
      expect((await cDaiToken.balanceOf(compoundModule.address)).toNumber()).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp.toNumber()).to.equal(expectedLendingBalanceOnComp);
    })

    it("Should be able to cash-out DAI right after lending up to max lending balance", async () => {
      const amount = utils.parseUnits("10");
      await daiToken.connect(lender).approve(compoundModule.address, amount);
      await compoundModule.connect(lender).lend(amount);
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender.getAddress())).onComp;
      const exchangeRate1 = await cDaiToken.exchangeRateStored();
      let toCashOut = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate1);

      // Check that lender cannot withdraw too much
      await expect(compoundModule.connect(lender).cashOut(toCashOut.add(utils.parseUnits("0.01")).toString())).to.be.reverted;

      // To improve as there is still dust after withdrawing
      const exchangeRate2 = await cDaiToken.exchangeRateStored();
      toCashOut = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate2);
      await compoundModule.connect(lender).cashOut(toCashOut);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp.toNumber()).to.gt(0);
    })

    it("Should be able to lend more DAI after already having lend DAI", async () => {
      const amount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("20");
      // Tx are done in different blocks
      await daiToken.connect(lender).approve(compoundModule.address, amountToApprove);
      await compoundModule.connect(lender).lend(amount);
      const exchangeRate1 = await cDaiToken.exchangeRateStored();
      await compoundModule.connect(lender).lend(amount);
      const exchangeRate2 = await cDaiToken.exchangeRateStored();
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect((await cDaiToken.balanceOf(compoundModule.address)).toNumber()).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp.toNumber()).to.equal(expectedLendingBalanceOnComp);
    });
  })

  xdescribe("Borrowing when there is no lenders", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onMorpho).to.equal(0);
    });

    it("Should revert when providing 0 as collateral", async () => {
      await expect(compoundModule.connect(lender).provideCollateral({ value: 0 })).to.be.revertedWith("Amount cannot be 0");
    });

    it("Should revert when borrowing 0", async () => {
      await expect(compoundModule.connect(lender).borrow(0)).to.be.revertedWith("Amount cannot be 0");
    });

    it("Should have the right amount of cETH in collateral after providing ETH as collateral", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const exchangeRateCurrent = await cDaiToken.exchangeRateStored();
      const expectedCollateralBalance = underlyingToCToken(10, exchangeRateCurrent, 18);
      expect(await compoundModule.collateralBalanceOf(borrower.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should be able to redeem collateral right after providing it", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const exchangeRateCurrent = await cDaiToken.exchangeRateStored();
      const expectedCollateralBalance = underlyingToCToken(amountToApprove, exchangeRateCurrent);
      expect(await compoundModule.collateralBalanceOf(borrower.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should not be able to borrow if no collateral provided", async () => {
      await expect(compoundModule.connect(borrower).borrow(0)).to.be.revertedWith("Amount cannot be 0");
    });

    it("Should be able to borrow on Compound after providing collateral up to max", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const collateralFactor = 0;
      const maxToBorrow = 0;
      await expect(compoundModule.connect(borrower).borrow(maxToBorrow)).to.be.revertedWith("Not enough collateral.");
    });

    it("Should not be able to borrow more than max allowed given an amount of collateral", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const collateralFactor = 0;
      const moreThanMaxToBorrow = BigNumber.from(100000000000000000000000000);
      await expect(compoundModule.connect(borrower).borrow(moreThanMaxToBorrow)).to.be.revertedWith("Not enough collateral.");
    });
  })

  xdescribe("Check interests accrued for a one borrower / one lender interaction on Morpho", () => {
    it("Lender and borrower should be in P2P interaction", async () => {
    });

    it("Lender and borrower should be in P2P interaction", async () => {
    });
  });

  xdescribe("Check permissions", () => {
  });

  xdescribe("Test attacks", async () => {
    it("Should not be DDOS by a lender or a group of lenders", async () => {
    });

    it("Should not be DDOS by a borrower or a group of borrowers", async () => {
    });

    it("Should not be subject to flash loan attacks", async () => {
    });

    it("Should be subjected to Oracle Manipulation attacs", async () => {
    });
  });
});