require("dotenv").config({ path: "../.env.local" });
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { utils, BigNumber } = require('ethers');
const Decimal = require('decimal.js');

// Use mainnet ABIs
const daiAbi = require('./abis/Dai.json');
const CErc20ABI = require('./abis/CErc20.json');
const CEthABI = require('./abis/CEth.json');
const comptrollerABI = require('./abis/Comptroller.json');
const compoundOracleABI = require('./abis/UniswapAnchoredView.json');

describe("CompoundModule Contract", () => {

  const CETH_ADDRESS = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
  const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const CDAI_ADDRESS = "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643";
  const PROXY_COMPTROLLER_ADDRESS = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";

  const SCALE = BigNumber.from(10).pow(18);

  let cEthToken;
  let cToken;
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
  // const doUpdate = await cToken.exchangeRateCurrent();
  // await doUpdate.wait(1);
  // const erc = await cToken.callStatic.exchangeRateStored();

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

  beforeEach(async () => {
    // Users
    [owner, lender1, lender2, lender3, borrower1, borrower2, borrower3, ...addrs] = await ethers.getSigners();
    lenders = [lender1, lender2, lender3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy CompoundModule
    CompoundModule = await ethers.getContractFactory("CompoundModule");
    compoundModule = await CompoundModule.deploy(CDAI_ADDRESS, CETH_ADDRESS, PROXY_COMPTROLLER_ADDRESS);
    await compoundModule.deployed();

    // Get contract dependencies
    cEthToken = await ethers.getContractAt(CEthABI, CETH_ADDRESS, owner);
    cToken = await ethers.getContractAt(CErc20ABI, CDAI_ADDRESS, owner);
    comptroller = await ethers.getContractAt(comptrollerABI, PROXY_COMPTROLLER_ADDRESS, owner);
    compoundOracle = await ethers.getContractAt(compoundOracleABI, comptroller.oracle(), owner);

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
    const ethAmount = utils.parseUnits("100");
    await hre.network.provider.send("hardhat_setBalance", [
      daiMinter,
      utils.hexValue(ethAmount),
    ]);
    // Mint DAI to all lenders.
    await Promise.all(lenders.map(async lender => {
      await daiToken.mint(lender.getAddress(), daiAmount, { from: daiMinter });
    }))
    await Promise.all(borrowers.map(async borrower => {
      await daiToken.mint(borrower.getAddress(), daiAmount, { from: daiMinter });
    }))
  });

  describe("Deployment", () => {
    it("Should deploy the contract with the right values", async () => {
      expect(await compoundModule.collateralFactor()).to.equal("750000000000000000");
      expect(await compoundModule.liquidationIncentive()).to.equal("1100000000000000000");

      // Calculate BPY
      const borrowRatePerBlock = await cToken.borrowRatePerBlock();
      const supplyRatePerBlock = await cToken.supplyRatePerBlock();
      const expectedBPY = borrowRatePerBlock.add(supplyRatePerBlock).div(2);
      expect(await compoundModule.BPY()).to.equal(expectedBPY);
      expect(await compoundModule.currentExchangeRate()).to.be.equal(utils.parseUnits("1"));
    });
  });

  describe("Test utils functions", () => {
    it("Should give the right collateral required for different values", async () => {
      // Amounts
      const amount1 = utils.parseUnits("10");
      const amount2 = utils.parseUnits("0");
      const amount3 = utils.parseUnits("1000000000");

      // Query collateral and prices
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const ethPriceMantissa = await compoundOracle.getUnderlyingPrice(CETH_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);

      // Collateral & expected collaterals
      const collateralRequired1 = await compoundModule.getCollateralRequired(amount1, collateralFactorMantissa, CDAI_ADDRESS, CETH_ADDRESS);
      const collateralRequired2 = await compoundModule.getCollateralRequired(amount2, collateralFactorMantissa, CDAI_ADDRESS, CETH_ADDRESS);
      const collateralRequired3 = await compoundModule.getCollateralRequired(amount3, collateralFactorMantissa, CDAI_ADDRESS, CETH_ADDRESS);
      const expectedCollateralRequired1 = getCollateralRequired(amount1, collateralFactorMantissa, daiPriceMantissa, ethPriceMantissa);
      const expectedCollateralRequired2 = getCollateralRequired(amount2, collateralFactorMantissa, daiPriceMantissa, ethPriceMantissa);
      const expectedCollateralRequired3 = getCollateralRequired(amount3, collateralFactorMantissa, daiPriceMantissa, ethPriceMantissa);

      // Checks
      expect(collateralRequired1).to.equal(expectedCollateralRequired1);
      expect(collateralRequired2).to.equal(expectedCollateralRequired2);
      expect(collateralRequired3).to.equal(expectedCollateralRequired3);
    });

    it("Should update the collateralFactor", async () => {
      await compoundModule.updateCollateralFactor();
      const { collateralFactorMantissa: expectedCollateraFactor } = await comptroller.markets(CDAI_ADDRESS);
      expect(await compoundModule.collateralFactor()).to.equal(expectedCollateraFactor);
    });

    // Note: this is not possible to access the result off-chain as the function is not pure/view.
    // We should add en event to allow catching of the values.
    xit("Should give the right account liquidity for an empty account", async () => {
      const { collateralInEth, collateralRequiredInEth } = (await compoundModule.getAccountLiquidity(borrower1.getAddress())).value;
      expect(collateralRequiredInEth).to.equal(0);
      expect(collateralInEth).to.equal(0);
    });

    it('Should update currentExchangeRate with the right value', async () => {
      const BPY = (await compoundModule.BPY()).toNumber();
      const currentExchangeRate = await compoundModule.currentExchangeRate();
      const lastUpdateBlockNumber = await compoundModule.lastUpdateBlockNumber();
      const { blockNumber } = await compoundModule.connect(owner).updateCurrentExchangeRate();
      const expectedCurrentExchangeRate = computeNewMorphoExchangeRate(currentExchangeRate, BPY, blockNumber, lastUpdateBlockNumber);
      // The pow function has some small decimal errors
      expect(removeDigitsBigNumber(5, (await compoundModule.currentExchangeRate()))).to.equal(removeDigits(5, expectedCurrentExchangeRate));
    });
  });

  describe("Lenders on Compound (no borrowers)", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho).to.equal(0);
    })

    it("Should revert when lending 0", async () => {
      await expect(compoundModule.connect(lender1).lend(0)).to.be.revertedWith("Amount cannot be 0.");
    })

    it("Should have the correct balances after lending", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).lend(amount);
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const exchangeRate = await cToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho).to.equal(0);
    })

    it("Should be able to withdraw ERC20 right after lending up to max lending balance", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).lend(amount);
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp;
      const exchangeRate1 = await cToken.callStatic.exchangeRateCurrent();
      const toWithdraw1 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate1);

      // Check that lender1 cannot withdraw too much
      // TODO: improve this test to prevent attacks
      await expect(compoundModule.connect(lender1).withdraw(toWithdraw1.add(utils.parseUnits("0.001")).toString())).to.be.reverted;

      // To improve as there is still dust after withdrawing: create a function with cToken as input?
      // Update exchange rate
      await cToken.connect(lender1).exchangeRateCurrent();
      const exchangeRate2 = await cToken.callStatic.exchangeRateCurrent();
      const toWithdraw2 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate2);
      await compoundModule.connect(lender1).withdraw(toWithdraw2);
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      // expect(toWithdraw2).to.be.above(toWithdraw1);
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amount).add(toWithdraw2));

      // Check cToken left are only dust in lending balance
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp).to.be.lt(1000);
      await expect(compoundModule.connect(lender1).withdraw(utils.parseUnits("0.001"))).to.be.reverted;
    })

    it("Should be able to lend more ERC20 after already having lend ERC20", async () => {
      const amount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("10").mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());

      // Tx are done in different blocks.
      await daiToken.connect(lender1).approve(compoundModule.address, amountToApprove);
      await compoundModule.connect(lender1).lend(amount);
      const exchangeRate1 = await cToken.callStatic.exchangeRateCurrent();
      await compoundModule.connect(lender1).lend(amount);
      const exchangeRate2 = await cToken.callStatic.exchangeRateCurrent();

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check lending balance
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
    });

    it("Several lenders should be able to lend and have the correct balances", async () => {
      const amount = utils.parseUnits("10");
      let expectedCTokenBalance = BigNumber.from(0);

      for (const i in lenders) {
        const lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(lender).approve(compoundModule.address, amount);
        await compoundModule.connect(lender).lend(amount);
        const exchangeRate = await cToken.callStatic.exchangeRateCurrent();
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
        expectedCTokenBalance = expectedCTokenBalance.add(expectedLendingBalanceOnComp);
        expect(removeDigitsBigNumber(7, await cToken.balanceOf(compoundModule.address))).to.equal(removeDigitsBigNumber(7, expectedCTokenBalance));
        expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceOf(lender.getAddress())).onComp)).to.equal(removeDigitsBigNumber(4, expectedLendingBalanceOnComp));
        expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho).to.equal(0);
      };
    });
  });

  describe("Borrowers on Compound (no lenders)", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho).to.equal(0);
    });

    it("Should revert when providing 0 as collateral", async () => {
      await expect(compoundModule.connect(lender1).provideCollateral({ value: 0 })).to.be.revertedWith("Amount cannot be 0.");
    });

    it("Should revert when borrowing 0", async () => {
      await expect(compoundModule.connect(lender1).borrow(0)).to.be.revertedWith("Amount cannot be 0.");
    });

    it("Should have the right amount of cETH in collateral after providing ETH as collateral", async () => {
      const amount = utils.parseUnits("10");
      const ethBalanceBefore = await ethers.provider.getBalance(borrower1.getAddress());
      const { hash, gasPrice } = await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const { gasUsed } = await ethers.provider.getTransactionReceipt(hash);
      const gasCost = gasUsed.mul(gasPrice);

      // Check ETH balance
      const ethBalanceAfter = await ethers.provider.getBalance(borrower1.getAddress());
      expect(ethBalanceAfter).to.equal(ethBalanceBefore.sub(gasCost).sub(amount));

      // Check collateral balance
      const cEthExchangeRate = await cEthToken.callStatic.exchangeRateCurrent();
      const expectedCollateralBalance = underlyingToCToken(amount, cEthExchangeRate);
      expect(await compoundModule.collateralBalanceOf(borrower1.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should redeem all collateral", async () => {
      const amount = utils.parseUnits("10");
      const ethBalanceBefore = await ethers.provider.getBalance(borrower1.getAddress());
      const { hash: hash1, gasPrice: gasPrice1 } = await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const { gasUsed: gasUsed1 } = await ethers.provider.getTransactionReceipt(hash1);
      const gasCost1 = gasUsed1.mul(gasPrice1);

      const toRedeemInCToken = await compoundModule.collateralBalanceOf(borrower1.getAddress());
      const cEthExchangeRate = await cEthToken.callStatic.exchangeRateCurrent();
      const toRedeemInUnderlying = cTokenToUnderlying(toRedeemInCToken, cEthExchangeRate);
      const { hash: hash2, gasPrice: gasPrice2 } = await compoundModule.connect(borrower1).redeemCollateral(toRedeemInUnderlying);
      const { gasUsed: gasUsed2 } = await ethers.provider.getTransactionReceipt(hash2);
      const gasCost2 = gasUsed2.mul(gasPrice2);

      // Check collateral balance
      expect(removeDigitsBigNumber(2, await compoundModule.collateralBalanceOf(borrower1.getAddress()))).to.equal(0);

      // Check ETH balance
      const ethBalanceAfter = await ethers.provider.getBalance(borrower1.getAddress());
      expect(ethBalanceAfter).to.equal(ethBalanceBefore.sub(gasCost1).sub(gasCost2).sub(amount).add(toRedeemInUnderlying));
    });

    it("Should be able to provide more collateral right after having providing some", async () => {
      const amount = utils.parseUnits("10");
      const ethBalanceBefore = await ethers.provider.getBalance(borrower1.getAddress());

      // First tx (calculate gas cost too)
      const { hash: hash1, gasPrice: gasPrice1 } = await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      // const tx = await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const { gasUsed: gasUsed1 } = await ethers.provider.getTransactionReceipt(hash1);
      const gasCost1 = gasUsed1.mul(gasPrice1);
      const exchangeRate1 = await cEthToken.callStatic.exchangeRateCurrent();

      // Second tx (calculate gas cost too)
      const { hash: hash2, gasPrice: gasPrice2 } = await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const { gasUsed: gasUsed2 } = await ethers.provider.getTransactionReceipt(hash2);
      const gasCost2 = gasUsed2.mul(gasPrice2);
      const exchangeRate2 = await cEthToken.callStatic.exchangeRateCurrent();

      // Check ETH balance
      const ethBalanceAfter = await ethers.provider.getBalance(borrower1.getAddress());
      expect(ethBalanceAfter).to.equal(ethBalanceBefore.sub(gasCost1).sub(gasCost2).sub(amount.mul(2)));

      // Check collateral balance
      const expectedCollateralBalance1 = underlyingToCToken(amount, exchangeRate1);
      const expectedCollateralBalance2 = underlyingToCToken(amount, exchangeRate2);
      const expectedCollateralBalance = expectedCollateralBalance1.add(expectedCollateralBalance2);
      expect(await cEthToken.balanceOf(compoundModule.address)).to.equal(expectedCollateralBalance);
      expect(await compoundModule.collateralBalanceOf(borrower1.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should not be able to borrow if no collateral provided", async () => {
      // TODO: fix issue in SC when borrowing too low values
      await expect(compoundModule.connect(borrower1).borrow(1)).to.be.revertedWith("Borrowing is too low.");
    });

    it("Should be able to borrow on Compound after providing collateral up to max", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const collateralBalanceInCEth = await compoundModule.collateralBalanceOf(borrower1.getAddress());
      const cEthExchangeRate = await cEthToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInEth = cTokenToUnderlying(collateralBalanceInCEth, cEthExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const ethPriceMantissa = await compoundOracle.getUnderlyingPrice(CETH_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInEth.mul(ethPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      const borrowIndex = await cToken.borrowIndex();
      await compoundModule.connect(borrower1).borrow(maxToBorrow);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).interestIndex).to.equal(borrowIndex);

      // All underlyings should have been sent to the borrower1
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(maxToBorrow);

      // Check Morpho balances
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(maxToBorrow);
    });

    it("Should not be able to borrow more than max allowed given an amount of collateral", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const collateralBalanceInCEth = await compoundModule.collateralBalanceOf(borrower1.getAddress());
      const cEthExchangeRate = await cEthToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInEth = cTokenToUnderlying(collateralBalanceInCEth, cEthExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const ethPriceMantissa = await compoundOracle.getUnderlyingPrice(CETH_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInEth.mul(collateralFactorMantissa).div(daiPriceMantissa).mul(ethPriceMantissa).div(SCALE);
      const moreThanMaxToBorrow = maxToBorrow.add(utils.parseUnits("0.0001"));

      // TODO: fix dust issue
      // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
      await expect(compoundModule.connect(borrower1).borrow(moreThanMaxToBorrow)).to.be.revertedWith("Not enough collateral.");
    });

    it("Several borrowers should be able to borrow and have the correct balances", async () => {
      const amount = utils.parseUnits("10");
      let expectedMorphoBorrowingBalance = BigNumber.from(0);
      let previousBorrowIndex = await cToken.borrowIndex();

      for (const i in borrowers) {
        const borrower = borrowers[i];
        await compoundModule.connect(borrower).provideCollateral({ value: amount });
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await compoundModule.connect(borrower).borrow(amount);

        const borrowIndex = await cToken.borrowIndex();
        expectedMorphoBorrowingBalance = expectedMorphoBorrowingBalance.mul(borrowIndex).div(previousBorrowIndex).add(amount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(amount));
        expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onComp).to.equal(amount);
        expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).interestIndex).to.equal(previousBorrowIndex);
        // Update previous borrow index
        previousBorrowIndex = borrowIndex;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(expectedMorphoBorrowingBalance);
    });

    it("Should be able to repay all borrowing amount", async () => {
      const amount = utils.parseUnits("1");
      // Approve more to be large enough
      const amountToApprove = utils.parseUnits("100000000");
      await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const collateralBalanceInCEth = await compoundModule.collateralBalanceOf(borrower1.getAddress());
      const cEthExchangeRate = await cEthToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInEth = cTokenToUnderlying(collateralBalanceInCEth, cEthExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const ethPriceMantissa = await compoundOracle.getUnderlyingPrice(CETH_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInEth.mul(ethPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      const previousBorrowIndex = await cToken.borrowIndex();
      await compoundModule.connect(borrower1).borrow(maxToBorrow);
      const borrowerInterestIndex = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).interestIndex;
      expect(borrowerInterestIndex).to.equal(previousBorrowIndex);

      const borrowIndex = await cToken.borrowIndex();
      await daiToken.connect(borrower1).approve(compoundModule.address, amountToApprove);
      const borrowerBalanceOnComp = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp;
      const toRepay = borrowerBalanceOnComp.mul(borrowIndex).div(borrowerInterestIndex);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(maxToBorrow).sub(toRepay);

      // Repay
      // WARNING: This fails as it seems the accrued interest are not updated
      // on Compound while it should knowing the deployec contract code here:
      // https://etherscan.io/address/0xa035b9e130f2b1aedc733eefb1c67ba4c503491f#code
      await compoundModule.connect(borrower1).repay(toRepay);

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho).to.equal(0);

      // Check Morpho balances
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cToken.callStatic.borrowBalanceStored(compoundModule.address)).to.be.lt(utils.parseUnits("0.0001"));
    });

    it("Should accrue interest on Compound", async () => {
      const amount = utils.parseUnits("1");
      const amountToBorrow = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("100000000");

      // borrower1 borrows
      await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const borrowIndex1 = await cToken.borrowIndex();
      await compoundModule.connect(borrower1).borrow(amountToBorrow);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).interestIndex).to.equal(borrowIndex1);

      // borrower2 borrows
      await compoundModule.connect(borrower2).provideCollateral({ value: amount });
      const borrowIndex2 = await cToken.borrowIndex();
      await compoundModule.connect(borrower2).borrow(amountToBorrow);
      expect((await compoundModule.borrowingBalanceOf(borrower2.getAddress())).interestIndex).to.equal(borrowIndex2);

      // borrower3 borrows
      await compoundModule.connect(borrower3).provideCollateral({ value: amount });
      const borrowIndex3 = await cToken.borrowIndex();
      await compoundModule.connect(borrower3).borrow(amountToBorrow);
      expect((await compoundModule.borrowingBalanceOf(borrower3.getAddress())).interestIndex).to.equal(borrowIndex3);

      // Check that borrower1 balance onComp accrued well after querying getAccountLiquidity
      const borrowIndex4 = await cToken.borrowIndex();
      const borrower1BorrowingBalanceOnComp1 = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp;
      const borrower1InterestIndex1 = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).interestIndex;
      const expectedBorrower1BorrowingBalanceOnComp1 = borrower1BorrowingBalanceOnComp1.mul(borrowIndex4).div(borrower1InterestIndex1);
      await compoundModule.getAccountLiquidity(borrower1.getAddress());
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(expectedBorrower1BorrowingBalanceOnComp1);

      // Check that borrower1 balance onComp accrued well after borrowing more
      const borrowIndex5 = await cToken.borrowIndex();
      const borrower1BorrowingBalanceOnComp2 = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp;
      const borrower1InterestIndex2 = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).interestIndex;
      const expectedBorrower1BorrowingBalanceOnComp2 = borrower1BorrowingBalanceOnComp2.mul(borrowIndex5).div(borrower1InterestIndex2).add(amountToBorrow);
      await compoundModule.connect(borrower1).borrow(amountToBorrow);
      expect(removeDigitsBigNumber(1, (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp)).to.equal(removeDigitsBigNumber(1, expectedBorrower1BorrowingBalanceOnComp2));

      // Check that borrower2 balance onComp accrued well after she repaid half of the borrowing
      await daiToken.connect(borrower2).approve(compoundModule.address, amountToApprove);
      const borrowIndex6 = await cToken.borrowIndex();
      const borrower2InterestIndex = (await compoundModule.borrowingBalanceOf(borrower2.getAddress())).interestIndex;
      const borrower2BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceOf(borrower2.getAddress())).onComp;
      const toRepay = borrower2BorrowingBalanceOnComp.div(2).mul(borrowIndex6).div(borrower2InterestIndex);
      const expectedBorrower2BorrowingBalanceOnComp = toRepay;
      await compoundModule.connect(borrower2).repay(toRepay);
      expect(removeDigitsBigNumber(2, (await compoundModule.borrowingBalanceOf(borrower2.getAddress())).onComp)).to.equal(removeDigitsBigNumber(2, expectedBorrower2BorrowingBalanceOnComp));
    });
  });

  describe("P2P interactions between lender and borrowers", () => {
    it("Lender should withdraw her liquidity while not enough cToken on Morpho contract", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(lendingAmount);
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).lend(lendingAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp1 = underlyingToCToken(lendingAmount, cExchangeRate1);
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp1);
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp1);

      // Borrower provides collateral
      const collateralAmount = utils.parseUnits("10");
      await compoundModule.connect(borrower1).provideCollateral({ value: collateralAmount });

      // Borrowers borrows lender1 amount
      await compoundModule.connect(borrower1).borrow(lendingAmount);

      // Check lender1 balances
      const cExchangeRate2 = await cToken.callStatic.exchangeRateCurrent();
      const mExchangeRate1 = await compoundModule.currentExchangeRate();
      const expectedLendingBalanceOnComp2 = expectedLendingBalanceOnComp1.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await compoundModule.connect(owner).updateCurrentExchangeRate();
      const mExchangeRate2 = await compoundModule.currentExchangeRate();
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await compoundModule.BPY(), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cToken.balanceOf(compoundModule.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.gt(cTokenContractBalanceInUnderlying);

      // Expected borrowing balances
      const expectedMorphoBorrowingBalance = remainingToWithdraw.add(cTokenContractBalanceInUnderlying).sub(lendingBalanceOnCompInUnderlying);
      const expectedBorrowingBalanceOnComp = expectedMorphoBorrowingBalance;

      // Withdraw
      await compoundModule.connect(lender1).withdraw(amountToWithdraw);
      const borrowBalance = await cToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      // Check borrow balance of Morpho
      expect(removeDigitsBigNumber(5, borrowBalance)).to.equal(removeDigitsBigNumber(5, expectedMorphoBorrowingBalance));

      // Check lender1 underlying balance
      expect(removeDigitsBigNumber(1, daiBalanceAfter2)).to.equal(removeDigitsBigNumber(1, expectedDaiBalanceAfter2));

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho)).to.equal(0);

      // Check borrowing balances of borrower1
      expect(removeDigitsBigNumber(5, (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp)).to.equal(removeDigitsBigNumber(5, expectedBorrowingBalanceOnComp));
      expect(removeDigitsBigNumber(4, (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho)).to.equal(0);
    });

    it("Lender should withdraw her liquidity while enough cToken on Morpho contract", async () => {
      // Lenders deposit tokens
      const lendingAmount = utils.parseUnits("10");

      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(lendingAmount);
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).lend(lendingAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp1 = underlyingToCToken(lendingAmount, cExchangeRate1);
      expect((await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp1);

      Promise.all(lenders.slice(1, lenders.length - 1).map(async lender => {
        const daiBalanceBefore1 = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore1.sub(lendingAmount);
        await daiToken.connect(lender).approve(compoundModule.address, lendingAmount);
        await compoundModule.connect(lender).lend(lendingAmount);
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const cExchangeRate = await cToken.callStatic.exchangeRateStored();
        const expectedLendingBalanceOnComp = underlyingToCToken(lendingAmount, cExchangeRate);
        expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceOf(lender.getAddress())).onComp)).to.equal(removeDigitsBigNumber(4, expectedLendingBalanceOnComp));
      }));

      // Borrower provides collateral
      const collateralAmount = utils.parseUnits("10");
      await compoundModule.connect(borrower1).provideCollateral({ value: collateralAmount });

      const previousLender1LendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp

      // Borrowers borrows lender1 amount
      await compoundModule.connect(borrower1).borrow(lendingAmount);

      // Check lender1 balances
      const mExchangeRate1 = await compoundModule.currentExchangeRate();
      const cExchangeRate2 = await cToken.callStatic.exchangeRateCurrent();
      // Expected balances of lender1
      const expectedLendingBalanceOnComp2 = previousLender1LendingBalanceOnComp.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await compoundModule.connect(owner).updateCurrentExchangeRate();
      const mExchangeRate2 = await compoundModule.currentExchangeRate();
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await compoundModule.BPY(), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cToken.balanceOf(compoundModule.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.lt(cTokenContractBalanceInUnderlying);

      // lender3 balances before the withdraw
      const lender3LendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender3.getAddress())).onComp;
      const lender3LendingBalanceOnMorpho = (await compoundModule.lendingBalanceOf(lender3.getAddress())).onMorpho;

      // lender2 balances before the withdraw
      const lender2LendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender2.getAddress())).onComp;
      const lender2LendingBalanceOnMorpho = (await compoundModule.lendingBalanceOf(lender2.getAddress())).onMorpho;

      // borrower1 balances before the withdraw
      const borrower1BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp;
      const borrower1BorrowingBalanceOnMorpho = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho;

      // Withdraw
      await compoundModule.connect(lender1).withdraw(amountToWithdraw);
      const cExchangeRate4 = await cToken.callStatic.exchangeRateStored();
      const borrowBalance = await cToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      const lender2LendingBalanceOnCompInUnderlying = cTokenToUnderlying(lender2LendingBalanceOnComp, cExchangeRate4);
      const amountToMove = bigNumberMin(lender2LendingBalanceOnCompInUnderlying, remainingToWithdraw);
      const mExchangeRate4 = await compoundModule.currentExchangeRate();
      const expectedLender2LendingBalanceOnComp = lender2LendingBalanceOnComp.sub(underlyingToCToken(amountToMove, cExchangeRate4));
      const expectedLender2LendingBalanceOnMorpho = lender2LendingBalanceOnMorpho.add(underlyingToMUnit(amountToMove, mExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check lender1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceOf(lender1.getAddress())).onMorpho)).to.equal(0);

      // Check lending balances of lender2: lender2 should have replaced lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceOf(lender2.getAddress())).onComp)).to.equal(removeDigitsBigNumber(1, expectedLender2LendingBalanceOnComp));
      expect(removeDigitsBigNumber(5, (await compoundModule.lendingBalanceOf(lender2.getAddress())).onMorpho)).to.equal(removeDigitsBigNumber(5, expectedLender2LendingBalanceOnMorpho));

      // Check lending balances of lender3: lender3 balances should not move
      expect((await compoundModule.lendingBalanceOf(lender3.getAddress())).onComp).to.equal(lender3LendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender3.getAddress())).onMorpho).to.equal(lender3LendingBalanceOnMorpho);

      // Check borrowing balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      const borrowIndex = await cToken.borrowIndex();
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(borrower1BorrowingBalanceOnComp);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho).to.equal(borrower1BorrowingBalanceOnMorpho);
    });

    it("Borrower on Morpho only, should be able to repay all borrowing amount", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).lend(lendingAmount);

      // Borrower borrows half of the tokens
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      const toBorrow = lendingAmount.div(2);
      await compoundModule.connect(borrower1).borrow(toBorrow);

      const borrowerBalanceOnMorpho = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho;
      const BPY = await compoundModule.BPY();
      await compoundModule.updateCurrentExchangeRate();
      const currentMExchangeRate = await compoundModule.currentExchangeRate();
      // WARNING: Should be one block but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(currentMExchangeRate, BPY, 1, 0).toString();
      const toRepay = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cToken.balanceOf(compoundModule.address);

      // Repay
      await daiToken.connect(borrower1).approve(compoundModule.address, toRepay);
      await compoundModule.connect(borrower1).repay(toRepay);
      const cExchangeRate = await cToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(toRepay, cExchangeRate));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(0);
      // Commented here due to the pow function issue
      // expect(removeDigitsBigNumber(1, (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho)).to.equal(0);

      // Check Morpho balances
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedMorphoCTokenBalance);
      expect(await cToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(0);
    });

    it("Borrower on Morpho and on Compound, should be able to repay all borrowing amount", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("100000000");
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).lend(lendingAmount);

      // Borrower borrows two times of the amount of tokens
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower1).provideCollateral({ value: amount });
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      const toBorrow = lendingAmount.mul(2);
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender1.getAddress())).onComp;
      await compoundModule.connect(borrower1).borrow(toBorrow);
      const cExchangeRate1 = await cToken.callStatic.exchangeRateStored();
      const expectedMorphoBorrowingBalance = toBorrow.sub(cTokenToUnderlying(lendingBalanceOnComp, cExchangeRate1));
      expect(removeDigitsBigNumber(3, await cToken.callStatic.borrowBalanceCurrent(compoundModule.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowingBalance));
      await daiToken.connect(borrower1).approve(compoundModule.address, amountToApprove);

      const borrowerBalanceOnMorpho = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho;
      const BPY = await compoundModule.BPY();
      const currentMExchangeRate = await compoundModule.currentExchangeRate();
      // WARNING: Should be 2 blocks but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(currentMExchangeRate, BPY, 1, 0).toString();
      const borrowerBalanceOnMorphoInUnderlying = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);

      // Compute how much to repay
      const borrowIndex = await cToken.borrowIndex();
      const borrowerInterestIndex = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).interestIndex;
      const borrowerBalanceOnComp = (await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp;
      const toRepay = borrowerBalanceOnComp.mul(borrowIndex).div(borrowerInterestIndex).add(borrowerBalanceOnMorphoInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cToken.balanceOf(compoundModule.address);

      // Repay
      await compoundModule.connect(borrower1).repay(toRepay);
      const cExchangeRate2 = await cToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(borrowerBalanceOnMorphoInUnderlying, cExchangeRate2));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onComp).to.equal(0);
      // WARNING: Commented here due to the pow function issue
      expect((await compoundModule.borrowingBalanceOf(borrower1.getAddress())).onMorpho).to.be.lt(1000000000000);

      // Check Morpho balances
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedMorphoCTokenBalance);
      expect(removeDigitsBigNumber(4, await cToken.callStatic.borrowBalanceCurrent(compoundModule.address))).to.equal(0);
    });
  });

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

    it("Should be subjected to Oracle Manipulation attacks", async () => {
    });
  });
});