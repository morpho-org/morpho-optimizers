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
    CompoundModule = await ethers.getContractFactory("CompoundModule");
    compoundModule = await CompoundModule.deploy(PROXY_COMPTROLLER_ADDRESS);
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

    await compoundModule.connect(owner).createMarkets([CDAI_ADDRESS, CUSDC_ADDRESS]);
    await compoundModule.connect(owner).listMarket(CDAI_ADDRESS);
    await compoundModule.connect(owner).updateThreshold(CUSDC_ADDRESS, 0, BigNumber.from(1).pow(6));
    await compoundModule.connect(owner).listMarket(CUSDC_ADDRESS);
  });

  describe("Lenders on Compound (no borrowers)", () => {
    it("test", async () => {
      console.log(await compoundModule.getMarketInfo(CDAI_ADDRESS));
    })

    it("Should revert when lending less than the required threshold", async () => {
      await expect(compoundModule.connect(lender1).lend(CDAI_ADDRESS, underlyingThreshold.sub(1))).to.be.revertedWith("Amount cannot be less than THRESHOLD.");
    })

    it("Should lend", async () => {
      const amount = utils.parseUnits("10");
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).lend(CDAI_ADDRESS, amount);
    })

    it("Should be able to withdraw ERC20 right after lending up to max lending balance", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).lend(CDAI_ADDRESS, amount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));
      await compoundModule.connect(lender1).withdraw(CDAI_ADDRESS, amount);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1);
    })

    it("Should be able to lend more ERC20 after already having lend ERC20", async () => {
      const amount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("10").mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());

      await daiToken.connect(lender1).approve(compoundModule.address, amountToApprove);
      await compoundModule.connect(lender1).lend(CDAI_ADDRESS, amount);
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      await compoundModule.connect(lender1).lend(CDAI_ADDRESS, amount);
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check lending balance
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
    });

    it("Several lenders should be able to lend and have the correct balances", async () => {
      const amount = utils.parseUnits("10");
      let expectedCTokenBalance = BigNumber.from(0);

      for (const i in lenders) {
        const lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(lender).approve(compoundModule.address, amount);
        await compoundModule.connect(lender).lend(CDAI_ADDRESS, amount);
        const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
        expectedCTokenBalance = expectedCTokenBalance.add(expectedLendingBalanceOnComp);
        expect(removeDigitsBigNumber(7, await cDaiToken.balanceOf(compoundModule.address))).to.equal(removeDigitsBigNumber(7, expectedCTokenBalance));
      };
    });
  });

  describe("Borrowers on Compound (no lenders)", () => {
    it("Should revert when providing 0 as collateral", async () => {
      await expect(compoundModule.connect(lender1).provideCollateral(CUSDC_ADDRESS, 0)).to.be.revertedWith("Amount cannot be 0.");
    });

    it("Should revert when borrowing less than threshold", async () => {
      const amount = toUSDC(utils.parseUnits("10"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await expect(compoundModule.connect(lender1).borrow(CDAI_ADDRESS, amount)).to.be.revertedWith("Amount cannot be less than THRESHOLD.");
    });

    it("Should redeem all collateral", async () => {
      const amount = toUSDC(utils.parseUnits("10"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      const usdcBalanceBefore1 = await usdcToken.balanceOf(borrower1.getAddress());
      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, amount);
      const usdcBalanceAfter1 = await usdcToken.balanceOf(borrower1.getAddress());
      expect(usdcBalanceAfter1).to.equal(usdcBalanceBefore1.sub(amount));
      await compoundModule.connect(borrower1).redeemCollateral(CUSDC_ADDRESS, amount);
      const usdcBalanceAfter2 = await usdcToken.balanceOf(borrower1.getAddress());
      expect(usdcBalanceAfter2).to.equal(usdcBalanceBefore1);
    });

    it("Should be able to provide more collateral right after having providing some", async () => {
      const amount = toUSDC(utils.parseUnits("10"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount.mul(2));
      const usdcBalanceBefore = await usdcToken.balanceOf(borrower1.getAddress());

      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, amount);
      const exchangeRate1 = await cUsdcToken.callStatic.exchangeRateCurrent();

      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, amount);
      const exchangeRate2 = await cUsdcToken.callStatic.exchangeRateCurrent();

      // Check collateral balance
      const expectedCUSDCBalance1 = underlyingToCToken(amount, exchangeRate1);
      const expectedCUSDCBalance2 = underlyingToCToken(amount, exchangeRate2);
      const expectedCUSDCBalance = expectedCUSDCBalance1.add(expectedCUSDCBalance2);
      const usdcBalanceAfter= await usdcToken.balanceOf(borrower1.getAddress());
      expect(await cUsdcToken.balanceOf(compoundModule.address)).to.equal(expectedCUSDCBalance);
      expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount.mul(2)));
    });

    it("Should not be able to borrow more than max allowed given an amount of collateral", async () => {
      const amount = toUSDC(utils.parseUnits("10"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, amount);
      const moreThanMaxToBorrow = utils.parseUnits("10");
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
        await compoundModule.connect(borrower).provideCollateral(CUSDC_ADDRESS, collateralAmount);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await compoundModule.connect(borrower).borrow(CDAI_ADDRESS, borrowedAmount);
        // We have one block delay from Compound
        const borrowIndex = await cDaiToken.borrowIndex();
        expectedMorphoBorrowingBalance = expectedMorphoBorrowingBalance.mul(borrowIndex).div(previousBorrowIndex).add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        previousBorrowIndex = borrowIndex;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(expectedMorphoBorrowingBalance);
    });
  });

  describe("P2P interactions between lender and borrowers", () => {
    it("Lender should withdraw her liquidity while not enough cDaiToken on Morpho contract", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      const daiLenderBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      const expectedLenderDaiBalanceAfter1 = daiLenderBalanceBefore1.sub(lendingAmount);
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).lend(CDAI_ADDRESS, lendingAmount);
      const daiLenderBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiLenderBalanceAfter1).to.equal(expectedLenderDaiBalanceAfter1);
      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedCDaiBalance1 = underlyingToCToken(lendingAmount, cExchangeRate1);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedCDaiBalance1);

      // Borrower provides collateral
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, collateralAmount);

      // Borrowers borrows lender1 amount
      const daiBorrowerBalanceBefore1 = await daiToken.balanceOf(borrower1.getAddress());
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, lendingAmount);
      const daiBorrowerBalanceAfter1 = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBorrowerBalanceAfter1).to.equal(daiBorrowerBalanceBefore1.add(lendingAmount));

      // Withdraw
      await compoundModule.connect(lender1).withdraw(CDAI_ADDRESS, lendingAmount);
    });

    it("Lender should withdraw her liquidity while enough cDaiToken on Morpho contract", async () => {
      const lendingAmount = utils.parseUnits("10");
      let lender;
      const expectedDaiBalance = await daiToken.balanceOf(lender1.getAddress());

      for (const i in lenders) {
        lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(lendingAmount);
        await daiToken.connect(lender).approve(compoundModule.address, lendingAmount);
        await compoundModule.connect(lender).lend(CDAI_ADDRESS, lendingAmount);
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      }

      // Borrower provides collateral
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, collateralAmount);

      // Borrowers borrows lender1 amount
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, lendingAmount);

      // Withdraw
      await compoundModule.connect(lender1).withdraw(CDAI_ADDRESS, lendingAmount);
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalance);
      // Check borrow balance of Morpho
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      expect(borrowBalance).to.equal(0);
    });

    it("Borrower on Morpho only, should be able to repay all borrowing amount", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).lend(CDAI_ADDRESS, lendingAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = lendingAmount.div(2);
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, collateralAmount);
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, toBorrow);

      // Repay
      await daiToken.connect(borrower1).approve(compoundModule.address, toBorrow);
      await compoundModule.connect(borrower1).repay(CDAI_ADDRESS, toBorrow);

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore);
    });

    it("Borrower on Morpho and on Compound, should be able to repay all borrowing amount", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).lend(CDAI_ADDRESS, lendingAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = toUSDC(utils.parseUnits("100"));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).provideCollateral(CUSDC_ADDRESS, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      const toBorrow = lendingAmount.mul(2);
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, toBorrow);

      // Repay
      await daiToken.connect(borrower1).approve(compoundModule.address, toBorrow);
      await compoundModule.connect(borrower1).repay(CDAI_ADDRESS, toBorrow);

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore);
    });
  });

  describe("Check permissions", () => {
    it("Only Owner should be bale to update thresholds", async () => {
      const newThreshold = utils.parseUnits("2");
      await compoundModule.connect(owner).updateThreshold(CUSDC_ADDRESS, 0, newThreshold);
      await compoundModule.connect(owner).updateThreshold(CUSDC_ADDRESS, 1, newThreshold);
      await compoundModule.connect(owner).updateThreshold(CUSDC_ADDRESS, 2, newThreshold);

      // Pointer out of bounds
      await expect(compoundModule.connect(owner).updateThreshold(CDAI_ADDRESS, 3, newThreshold)).to.be.reverted;

      // Other accounts than Owner
      await expect(compoundModule.connect(lender1).updateThreshold(CUSDC_ADDRESS, 2, newThreshold)).to.be.reverted;
      await expect(compoundModule.connect(borrower1).updateThreshold(CUSDC_ADDRESS, 2, newThreshold)).to.be.reverted;
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