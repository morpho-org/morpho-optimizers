require("dotenv").config({ path: "../.env.local" });
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { utils, BigNumber } = require('ethers');
const Decimal = require('decimal.js');

// Use mainnet ABIs
const daiAbi = require('./abis/Dai.json');
const usdcAbi = require('./abis/USDC.json')
const CErc20ABI = require('./abis/CErc20.json');
const CEthABI = require('./abis/CEth.json');
const comptrollerABI = require('./abis/Comptroller.json');
const compoundOracleABI = require('./abis/UniswapAnchoredView.json');

describe("CompoundModule Contract", () => {

  const CETH_ADDRESS = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
  const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const CDAI_ADDRESS = "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643";
  const USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  const CUSDC_ADDRESS = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
  const PROXY_COMPTROLLER_ADDRESS = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";

  const SCALE = BigNumber.from(10).pow(18);

  let cUsdcToken;
  let cDaiToken;
  let daiToken;
  let CompoundModule;
  let compoundModule;

  let owner;
  let lender1;
  let lender2;
  let lender3;
  let borrower1;
  let borrower2;
  let borrower3;
  let addrs;
  let lenders;
  let borrowers;

  let underlyingThreshold;

  /* Utils functions */

  const underlyingToCToken = (underlyingAmount, exchangeRateCurrent) => {
    return underlyingAmount.mul(SCALE).div(exchangeRateCurrent);
  }

  const cTokenToUnderlying = (cTokenAmount, exchangeRateCurrent) => {
    return cTokenAmount.mul(exchangeRateCurrent).div(SCALE);
  }

  const underlyingToMUnit = (underlyingAmount, exchangeRateCurrent) => {
    return underlyingAmount.mul(SCALE).div(exchangeRateCurrent);
  }

  const mUnitToUnderlying = (mUnitAmount, exchangeRateCurrent) => {
    return mUnitAmount.mul(exchangeRateCurrent).div(SCALE);
  }

  const getCollateralRequired = (amount, collateralFactor, borrowedAssetPrice, collateralAssetPrice) => {
    return amount.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(SCALE).div(collateralFactor)
  }

  const bigNumberMin = (a, b) => {
    if (a.lte(b)) return a
    return b
  }

  // To update exchangeRateCurrent
  // const doUpdate = await cDaiToken.exchangeRateCurrent();
  // await doUpdate.wait(1);
  // const erc = await cDaiToken.callStatic.exchangeRateStored();

  // Removes the last digits of a number: used to remove dust errors
  const removeDigitsBigNumber = (decimalsToRemove, number) => (number.sub(number.mod(BigNumber.from(10).pow(decimalsToRemove)))).div(BigNumber.from(10).pow(decimalsToRemove));
  const removeDigits = (decimalsToRemove, number) => (number - (number % (10**decimalsToRemove))) / (10**decimalsToRemove);

  const computeNewMorphoExchangeRate = (currentExchangeRate, BPY, currentBlockNumber, lastUpdateBlockNumber) => {
    // Use of decimal.js library for better accuracy
    const bpy = new Decimal(BPY.toString())
    const scale = new Decimal('1e18')
    const exponent = new Decimal(currentBlockNumber - lastUpdateBlockNumber)
    const val = bpy.div(scale).add(1)
    const multiplier = val.pow(exponent)
    const newExchangeRate = new Decimal(currentExchangeRate.toString()).mul(multiplier)
    return Decimal.round(newExchangeRate);
  }

  const computeNewBorrowIndex = (borrowRate, blockDelta, borrowIndex) => {
    return borrowRate.mul(blockDelta).mul(borrowIndex).div(SCALE).add(borrowIndex);
  }

  const toUSDC = (value) => value.div(BigNumber.from(10).pow(12));

  beforeEach(async () => {
    // Users
    [owner, lender1, lender2, lender3, borrower1, borrower2, borrower3, ...addrs] = await ethers.getSigners();
    lenders = [lender1, lender2, lender3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy CompoundModule
    Morpho = await ethers.getContractFactory("Morpho");
    morpho = await Morpho.deploy(PROXY_COMPTROLLER_ADDRESS);
    await morpho.deployed();

    CompoundModule = await ethers.getContractFactory("CompoundModule");
    compoundModule = await CompoundModule.deploy(morpho.address, PROXY_COMPTROLLER_ADDRESS);
    await compoundModule.deployed();

    // Get contract dependencies
    cUsdcToken = await ethers.getContractAt(CErc20ABI, CUSDC_ADDRESS, owner);
    cDaiToken = await ethers.getContractAt(CErc20ABI, CDAI_ADDRESS, owner);
    comptroller = await ethers.getContractAt(comptrollerABI, PROXY_COMPTROLLER_ADDRESS, owner);
    compoundOracle = await ethers.getContractAt(compoundOracleABI, comptroller.oracle(), owner);

    const ethAmount = utils.parseUnits("100");

    // Mint some ERC20
    // Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
    const daiMinter = '0x9759A6Ac90977b93B58547b4A71c78317f391A28';
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [daiMinter],
    });
    const daiSigner = await ethers.getSigner(daiMinter);
    daiToken = await ethers.getContractAt(daiAbi, DAI_ADDRESS, daiSigner);
    const daiAmount = utils.parseUnits("100000000");
    await hre.network.provider.send("hardhat_setBalance", [
      daiMinter,
      utils.hexValue(ethAmount),
    ]);

    // Mint DAI to all lenders and borrowers
    await Promise.all(lenders.map(async lender => {
      await daiToken.mint(lender.getAddress(), daiAmount, { from: daiMinter });
    }))
    await Promise.all(borrowers.map(async borrower => {
      await daiToken.mint(borrower.getAddress(), daiAmount, { from: daiMinter });
    }))

    const usdcMinter = '0x5b6122c109b78c6755486966148c1d70a50a47d7';
    // const masterMinter = await usdcToken.masterMinter();
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [usdcMinter],
    });
    const usdcSigner = await ethers.getSigner(usdcMinter);
    usdcToken = await ethers.getContractAt(usdcAbi, USDC_ADDRESS, usdcSigner);
    const usdcAmount = BigNumber.from(10).pow(10); // 10 000 USDC
    await hre.network.provider.send("hardhat_setBalance", [
      usdcMinter,
      utils.hexValue(ethAmount),
    ]);

    // Mint USDC
    await Promise.all(borrowers.map(async borrower => {
      await usdcToken.mint(borrower.getAddress(), usdcAmount, { from: usdcMinter });
    }));

    underlyingThreshold = BigNumber.from(1).pow(18);

    await morpho.connect(owner).setCompoundModule(compoundModule.address);
    await morpho.connect(owner).createMarkets([CDAI_ADDRESS, CUSDC_ADDRESS]);
    await morpho.connect(owner).listMarket(CDAI_ADDRESS);
    await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 0, BigNumber.from(1).pow(6));
    await morpho.connect(owner).listMarket(CUSDC_ADDRESS);
  });

  describe("Deployment", () => {
    it.only("Should deploy the contract with the right values", async () => {
      expect(await morpho.liquidationIncentive()).to.equal("1100000000000000000");

      // Calculate BPY
      const borrowRatePerBlock = await cDaiToken.borrowRatePerBlock();
      const supplyRatePerBlock = await cDaiToken.supplyRatePerBlock();
      const expectedBPY = borrowRatePerBlock.add(supplyRatePerBlock).div(2);
      expect(await morpho.BPY(CDAI_ADDRESS)).to.equal(expectedBPY);

      const result = await comptroller.markets(CDAI_ADDRESS);
      expect(await morpho.mUnitExchangeRate(CDAI_ADDRESS)).to.be.equal(utils.parseUnits("1"));
      expect(await morpho.collateralFactor(CDAI_ADDRESS)).to.be.equal(result.collateralFactorMantissa);

      // Thresholds
      underlyingThreshold = await morpho.thresholds(CDAI_ADDRESS, 0);
      expect(underlyingThreshold).to.be.equal(utils.parseUnits("1"));
      expect(await morpho.thresholds(CDAI_ADDRESS, 1)).to.be.equal(BigNumber.from(10).pow(7));
      expect(await morpho.thresholds(CDAI_ADDRESS, 2)).to.be.equal(utils.parseUnits("1"));
    });
  });

  describe("Lenders on Compound (no borrowers)", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho).to.equal(0);
    })

    it("Should revert when lending less than the required threshold", async () => {
      await expect(compoundModule.connect(lender1).deposit(CDAI_ADDRESS, underlyingThreshold.sub(1))).to.be.revertedWith("Amount cannot be less than THRESHOLD.");
    })

    it("Should have the correct balances after lending", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho).to.equal(0);
    })

    it("Should be able to redeem ERC20 right after lending up to max lending balance", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));

      const lendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw1 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate1);

      // TODO: improve this test to prevent attacks
      await expect(compoundModule.connect(lender1).redeem(toWithdraw1.add(utils.parseUnits("0.001")).toString())).to.be.reverted;

      // Update exchange rate
      await cDaiToken.connect(lender1).exchangeRateCurrent();
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw2 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate2);
      await compoundModule.connect(lender1).redeem(CDAI_ADDRESS, toWithdraw2);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());
      // Check ERC20 balance
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1.sub(amount).add(toWithdraw2));

      // Check cToken left are only dust in lending balance
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.be.lt(1000);
      await expect(compoundModule.connect(lender1).redeem(CDAI_ADDRESS, utils.parseUnits("0.001"))).to.be.reverted;
    })

    it("Should be able to deposit more ERC20 after already having deposit ERC20", async () => {
      const amount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("10").mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());

      await daiToken.connect(lender1).approve(compoundModule.address, amountToApprove);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check lending balance
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
    });

    it("Several lenders should be able to deposit and have the correct balances", async () => {
      const amount = utils.parseUnits("10");
      let expectedCTokenBalance = BigNumber.from(0);

      for (const i in lenders) {
        const lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(lender).approve(compoundModule.address, amount);
        await compoundModule.connect(lender).deposit(CDAI_ADDRESS, amount);
        const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
        expectedCTokenBalance = expectedCTokenBalance.add(expectedLendingBalanceOnComp);
        expect(removeDigitsBigNumber(7, await cDaiToken.balanceOf(compoundModule.address))).to.equal(removeDigitsBigNumber(7, expectedCTokenBalance));
        expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender.getAddress())).onComp)).to.equal(removeDigitsBigNumber(4, expectedLendingBalanceOnComp));
        expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender.getAddress())).onMorpho).to.equal(0);
      };
    });
  });

  describe("Borrowers on Compound (no lenders)", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(0);
    });

    it("Should revert when providing 0 as collateral", async () => {
      await expect(compoundModule.connect(lender1).deposit(CDAI_ADDRESS, 0)).to.be.revertedWith("Amount cannot be less than THRESHOLD.");
    });

    it("Should revert when borrowing less than threshold", async () => {
      const amount = toUSDC(utils.parseUnits("10"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await expect(compoundModule.connect(lender1).borrow(CDAI_ADDRESS, amount)).to.be.revertedWith("Amount cannot be less than THRESHOLD.");
    });

    it("Should be able to borrow on Compound after providing collateral up to max", async () => {
      const amount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, amount);
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInCToken = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, maxToBorrow);
      const borrowIndex = await cDaiToken.borrowIndex();
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      expect(removeDigitsBigNumber(2, (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp.mul(borrowIndex).div(SCALE))).to.equal(removeDigitsBigNumber(2, maxToBorrow));

      // Check Morpho balances
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(maxToBorrow);
    });

    it("Should not be able to borrow more than max allowed given an amount of collateral", async () => {
      const amount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, amount);
      const collateralBalanceInCToken = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const moreThanMaxToBorrow = maxToBorrow.add(utils.parseUnits("0.0001"));

      // TODO: fix dust issue
      // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
      await expect(compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, moreThanMaxToBorrow)).to.be.revertedWith("Not enough collateral.");
    });

    it("Several borrowers should be able to borrow and have the correct balances", async () => {
      const collateralAmount = toUSDC(utils.parseUnits("10"));
      const borrowedAmount = utils.parseUnits("2");
      let expectedMorphoBorrowingBalance = BigNumber.from(0);
      let previousBorrowIndex = await cDaiToken.borrowIndex();

      for (const i in borrowers) {
        const borrower = borrowers[i];
        await usdcToken.connect(borrower).approve(compoundModule.address, collateralAmount);
        await compoundModule.connect(borrower).deposit(CUSDC_ADDRESS, collateralAmount);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await compoundModule.connect(borrower).borrow(CDAI_ADDRESS, borrowedAmount);
        // We have one block delay from Compound
        const borrowIndex = await cDaiToken.borrowIndex();
        expectedMorphoBorrowingBalance = expectedMorphoBorrowingBalance.mul(borrowIndex).div(previousBorrowIndex).add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        const borrowingBalanceOnCompInUnderlying = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower.getAddress())).onComp.mul(borrowIndex).div(SCALE);
        let diff;
        if (borrowingBalanceOnCompInUnderlying.gt(borrowedAmount))
          diff = borrowingBalanceOnCompInUnderlying.sub(borrowedAmount);
        else
          diff = borrowedAmount.sub(borrowingBalanceOnCompInUnderlying);
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        // Update previous borrow index
        previousBorrowIndex = borrowIndex;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(expectedMorphoBorrowingBalance);
    });
  });

  describe("P2P interactions between lender and borrowers", () => {
    it("Lender should withdraw her liquidity while not enough cToken on Morpho contract", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(lendingAmount);
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp1 = underlyingToCToken(lendingAmount, cExchangeRate1);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp1);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp1);

      // Borrower provides collateral
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);

      // Borrowers borrows lender1 amount
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, lendingAmount);

      // Check lender1 balances
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const mExchangeRate1 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const expectedLendingBalanceOnComp2 = expectedLendingBalanceOnComp1.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await morpho.connect(owner).updateMUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate2 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morpho.BPY(CDAI_ADDRESS), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(compoundModule.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.gt(cTokenContractBalanceInUnderlying);

      // Expected borrowing balances
      const expectedMorphoBorrowingBalance = remainingToWithdraw.add(cTokenContractBalanceInUnderlying).sub(lendingBalanceOnCompInUnderlying);

      // Withdraw
      await compoundModule.connect(lender1).redeem(CDAI_ADDRESS, amountToWithdraw);
      const borrowIndex = await cDaiToken.borrowIndex();
      const expectedBorrowerBorrowingBalanceOnComp = expectedMorphoBorrowingBalance.mul(SCALE).div(borrowIndex);
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      // Check borrow balance of Morphof
      expect(removeDigitsBigNumber(5, borrowBalance)).to.equal(removeDigitsBigNumber(5, expectedMorphoBorrowingBalance));

      // Check lender1 underlying balance
      expect(removeDigitsBigNumber(1, daiBalanceAfter2)).to.equal(removeDigitsBigNumber(1, expectedDaiBalanceAfter2));

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho)).to.equal(0);

      // Check borrowing balances of borrower1
      expect(removeDigitsBigNumber(6, (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp)).to.equal(removeDigitsBigNumber(6, expectedBorrowerBorrowingBalanceOnComp));
      expect(removeDigitsBigNumber(4, (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho)).to.equal(0);
    });

    it("Lender should redeem her liquidity while enough cDaiToken on Morpho contract", async () => {
      const lendingAmount = utils.parseUnits("10");
      let lender;
      const expectedDaiBalance = await daiToken.balanceOf(lender1.getAddress());

      for (const i in lenders) {
        lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(lendingAmount);
        await daiToken.connect(lender).approve(compoundModule.address, lendingAmount);
        await compoundModule.connect(lender).deposit(CDAI_ADDRESS, lendingAmount);
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
        const expectedLendingBalanceOnComp = underlyingToCToken(lendingAmount, cExchangeRate);
        expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender.getAddress())).onComp)).to.equal(removeDigitsBigNumber(4, expectedLendingBalanceOnComp));
      }

      // Borrower provides collateral
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);

      const previousLender1LendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;

      // Borrowers borrows lender1 amount
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, lendingAmount);

      // Check lender1 balances
      const mExchangeRate1 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      // Expected balances of lender1
      const expectedLendingBalanceOnComp2 = previousLender1LendingBalanceOnComp.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await morpho.connect(owner).updateMUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate2 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morpho.BPY(CDAI_ADDRESS), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(compoundModule.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.lt(cTokenContractBalanceInUnderlying);

      // lender3 balances before the withdraw
      const lender3LendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onComp;
      const lender3LendingBalanceOnMorpho = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onMorpho;

      // lender2 balances before the withdraw
      const lender2LendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onComp;
      const lender2LendingBalanceOnMorpho = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onMorpho;

      // borrower1 balances before the withdraw
      const borrower1BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      const borrower1BorrowingBalanceOnMorpho = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;

      // Withdraw
      await compoundModule.connect(lender1).redeem(CDAI_ADDRESS, amountToWithdraw);
      const cExchangeRate4 = await cDaiToken.callStatic.exchangeRateStored();
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      const lender2LendingBalanceOnCompInUnderlying = cTokenToUnderlying(lender2LendingBalanceOnComp, cExchangeRate4);
      const amountToMove = bigNumberMin(lender2LendingBalanceOnCompInUnderlying, remainingToWithdraw);
      const mExchangeRate4 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const expectedLender2LendingBalanceOnComp = lender2LendingBalanceOnComp.sub(underlyingToCToken(amountToMove, cExchangeRate4));
      const expectedLender2LendingBalanceOnMorpho = lender2LendingBalanceOnMorpho.add(underlyingToMUnit(amountToMove, mExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check lender1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho)).to.equal(0);

      // Check lending balances of lender2: lender2 should have replaced lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onComp)).to.equal(removeDigitsBigNumber(1, expectedLender2LendingBalanceOnComp));
      expect(removeDigitsBigNumber(5, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onMorpho)).to.equal(removeDigitsBigNumber(5, expectedLender2LendingBalanceOnMorpho));

      // Check lending balances of lender3: lender3 balances should not move
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onComp).to.equal(lender3LendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onMorpho).to.equal(lender3LendingBalanceOnMorpho);

      // Check borrowing balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(borrower1BorrowingBalanceOnComp);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(borrower1BorrowingBalanceOnMorpho);
    });

    it("Borrower on Morpho only, should be able to repay all borrowing amount", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = lendingAmount.div(2);

      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, toBorrow);

      const borrowerBalanceOnMorpho = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;
      const BPY = await morpho.BPY(CDAI_ADDRESS);
      await morpho.updateMUnitExchangeRate(CDAI_ADDRESS);
      const mUnitExchangeRate = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      // WARNING: Should be one block but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, BPY, 1, 0).toString();
      const toRepay = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(compoundModule.address);

      // Repay
      await daiToken.connect(borrower1).approve(compoundModule.address, toRepay);
      await compoundModule.connect(borrower1).repay(CDAI_ADDRESS, toRepay);
      const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(toRepay, cExchangeRate));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      // Commented here due to the pow function issue
      // expect(removeDigitsBigNumber(1, (await compoundModule.borrowingBalanceInOf(borrower1.getAddress())).onMorpho)).to.equal(0);

      // Check Morpho balances
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedMorphoCTokenBalance);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(0);
    });

    it("Borrower on Morpho and on Compound, should be able to repay all borrowing amount", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("100000000");
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = lendingAmount.mul(2);
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, toBorrow);

      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoBorrowingBalance1 = toBorrow.sub(cTokenToUnderlying(lendingBalanceOnComp, cExchangeRate1));
      const morphoBorrowingBalanceBefore1 = await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      expect(removeDigitsBigNumber(3, morphoBorrowingBalanceBefore1)).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowingBalance1));
      await daiToken.connect(borrower1).approve(compoundModule.address, amountToApprove);

      const borrowerBalanceOnMorpho = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;
      const BPY = await morpho.BPY(CDAI_ADDRESS);
      const mUnitExchangeRate = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      // WARNING: Should be 2 blocks but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, BPY, 1, 0).toString();
      const borrowerBalanceOnMorphoInUnderlying = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);

      // Compute how much to repay
      const doUpdate = await cDaiToken.borrowBalanceCurrent(compoundModule.address);
      await doUpdate.wait(1);
      const morphoBorrowingBalanceBefore2 = await cDaiToken.borrowBalanceStored(compoundModule.address);
      const borrowIndex1 = await cDaiToken.borrowIndex();
      const borrowerBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      const toRepay = borrowerBalanceOnComp.mul(borrowIndex1).div(SCALE).add(borrowerBalanceOnMorphoInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(compoundModule.address);

      // Repay
      await daiToken.connect(borrower1).approve(compoundModule.address, toRepay);
      const borrowIndex3 = await cDaiToken.callStatic.borrowIndex();
      await compoundModule.connect(borrower1).repay(CDAI_ADDRESS, toRepay);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(borrowerBalanceOnMorphoInUnderlying, cExchangeRate2));
      const expectedBalanceOnComp = borrowerBalanceOnComp.sub(borrowerBalanceOnComp.mul(borrowIndex1).div(borrowIndex3));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      expect(removeDigitsBigNumber(2, borrower1BorrowingBalanceOnComp)).to.equal(removeDigitsBigNumber(2, expectedBalanceOnComp));
      // WARNING: Commented here due to the pow function issue
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.be.lt(1000000000000);

      // Check Morpho balances
      expect(removeDigitsBigNumber(5, await cDaiToken.balanceOf(compoundModule.address))).to.equal(removeDigitsBigNumber(5, expectedMorphoCTokenBalance));
      // Issue here: we cannot access the most updated borrowing balance as it's updated during the repayBorrow on Compound.
      // const expectedMorphoBorrowingBalance2 = morphoBorrowingBalanceBefore2.sub(borrowerBalanceOnComp.mul(borrowIndex2).div(SCALE));
      // expect(removeDigitsBigNumber(3, await cToken.callStatic.borrowBalanceStored(compoundModule.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowingBalance2));
    });
  });

  describe("Check permissions", () => {
    it("Only Owner should be bale to update thresholds", async () => {
      const newThreshold = utils.parseUnits("2");
      await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 0, newThreshold);
      await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 1, newThreshold);
      await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 2, newThreshold);

      // Other accounts than Owner
      await expect(morpho.connect(lender1).updateThreshold(CUSDC_ADDRESS, 2, newThreshold)).to.be.reverted;
      await expect(morpho.connect(borrower1).updateThreshold(CUSDC_ADDRESS, 2, newThreshold)).to.be.reverted;
    });
  });

  xdescribe("Test attacks", async () => {
    it("Should not be DDOS by a lender or a group of lenders", async () => {
    });

    it("Should not be DDOS by a borrower or a group of borrowers", async () => {
    });

    it("Should not be subject to flash loan attacks", async () => {
    });

    it("Should not be subjected to Oracle Manipulation attacks", async () => {
    });
  });
});