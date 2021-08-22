const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { utils, BigNumber } = require('ethers');

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

  const gasPrice = BigNumber.from(8000000000); // Default value
  const SCALE = BigNumber.from(10).pow(18);

  let cEthToken;
  let cToken;
  let daiToken;
  let CompoundModule;
  let compoundModule;

  let owner;
  let lender;
  let borrower;
  let addrs;

  // Utils functions

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

  // Removes the mast 5 digits of a number: used to prevent dust errors
  const removeDigitsBigNumber = (number) => (number.sub(number.mod(100000))).div(100000);
  const removeDigits = (number) => (number - (number % 100000)) / 100000;

  const computeNewMorphoExchangeRate = (currentExchangeRate, BPY, currentBlockNumber, lastUpdateBlockNumber) => {
    return currentExchangeRate * (1 + BPY / 1e18) ** BigNumber.from(currentBlockNumber).sub(lastUpdateBlockNumber).toNumber();
  }

  beforeEach(async () => {
    // Users
    [lender, borrower, owner, ...addrs] = await ethers.getSigners();

    // Deploy CompoundModule
    CompoundModule = await ethers.getContractFactory("CompoundModule");
    compoundModule = await CompoundModule.deploy(CDAI_ADDRESS);
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
    const daiAmount = utils.parseUnits("10000");
    const ethAmount = utils.parseUnits("100");
    await hre.network.provider.send("hardhat_setBalance", [
      daiMinter,
      utils.hexValue(ethAmount),
    ]);
    await daiToken.mint(lender.getAddress(), daiAmount, { from: daiMinter });
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
      const { collateralInEth, collateralRequiredInEth } = (await compoundModule.getAccountLiquidity(borrower.getAddress())).value;
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
      expect(removeDigitsBigNumber((await compoundModule.currentExchangeRate()))).to.equal(removeDigits(expectedCurrentExchangeRate));
    });
  });

  describe("Lending when there is no borrowers", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho).to.equal(0);
    })

    it("Should revert when lending 0", async () => {
      await expect(compoundModule.connect(lender).lend(0)).to.be.revertedWith("Amount cannot be 0.");
    })

    it("Should have the right amount of cToken onComp after lending ERC20", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(lender).approve(compoundModule.address, amount);
      await compoundModule.connect(lender).lend(amount);
      const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const exchangeRate = await cToken.exchangeRateStored();
      const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
    })

    it("Should be able to withdraw ERC20 right after lending up to max lending balance", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
      await daiToken.connect(lender).approve(compoundModule.address, amount);
      await compoundModule.connect(lender).lend(amount);
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender.getAddress())).onComp;
      const exchangeRate1 = await cToken.exchangeRateStored();
      const toWithdraw1 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate1);

      // Check that lender cannot withdraw too much
      // TODO: improve this test to prevent attacks
      await expect(compoundModule.connect(lender).withdraw(toWithdraw1.add(utils.parseUnits("0.001")).toString())).to.be.reverted;

      // To improve as there is still dust after withdrawing: create a function with cToken as input?
      // Update exchange rate
      await cToken.connect(lender).exchangeRateCurrent();
      const exchangeRate2 = await cToken.exchangeRateStored();
      const toWithdraw2 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate2);
      await compoundModule.connect(lender).withdraw(toWithdraw2);
      const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

      // Check ERC20 balance
      // expect(toWithdraw2).to.be.above(toWithdraw1);
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amount).add(toWithdraw2));

      // Check cToken left are only dust in lending balance
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.lt(1000);
      await expect(compoundModule.connect(lender).withdraw(utils.parseUnits("0.001"))).to.be.reverted;
    })

    it("Should be able to lend more ERC20 after already having lend ERC20", async () => {
      const amount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("10").mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());

      // Tx are done in different blocks.
      await daiToken.connect(lender).approve(compoundModule.address, amountToApprove);
      await compoundModule.connect(lender).lend(amount);
      const exchangeRate1 = await cToken.exchangeRateStored();
      await compoundModule.connect(lender).lend(amount);
      const exchangeRate2 = await cToken.exchangeRateStored();

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check lending balance
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
    });
  })

  describe("Borrowing when there is no lenders", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onMorpho).to.equal(0);
    });

    it("Should revert when providing 0 as collateral", async () => {
      await expect(compoundModule.connect(lender).provideCollateral({ value: 0 })).to.be.revertedWith("Amount cannot be 0.");
    });

    it("Should revert when borrowing 0", async () => {
      await expect(compoundModule.connect(lender).borrow(0)).to.be.revertedWith("Amount cannot be 0.");
    });

    it("Should have the right amount of cETH in collateral after providing ETH as collateral", async () => {
      const amount = utils.parseUnits("10");
      const ethBalanceBefore = await ethers.provider.getBalance(borrower.getAddress());
      const { hash } = await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const { gasUsed } = await ethers.provider.getTransactionReceipt(hash);
      const gasCost = gasUsed.mul(gasPrice);

      // Check ETH balance
      const ethBalanceAfter = await ethers.provider.getBalance(borrower.getAddress());
      expect(ethBalanceAfter).to.equal(ethBalanceBefore.sub(gasCost).sub(amount));

      // Check collateral balance
      const exchangeRate = await cEthToken.exchangeRateStored();
      const expectedCollateralBalance = underlyingToCToken(amount, exchangeRate);
      expect(await compoundModule.collateralBalanceOf(borrower.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should be able to provide more collateral right after having providing some", async () => {
      const amount = utils.parseUnits("10");
      const ethBalanceBefore = await ethers.provider.getBalance(borrower.getAddress());

      // First tx (calculate gas cost too)
      const { hash: hash1 } = await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const { gasUsed: gasUsed1 } = await ethers.provider.getTransactionReceipt(hash1);
      const gasCost1 = gasUsed1.mul(gasPrice);
      const exchangeRate1 = await cEthToken.exchangeRateStored();

      // Second tx (calculate gas cost too)
      const { hash: hash2 } = await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const { gasUsed: gasUsed2 } = await ethers.provider.getTransactionReceipt(hash2);
      const gasCost2 = gasUsed2.mul(gasPrice);
      const exchangeRate2 = await cEthToken.exchangeRateStored();

      // Check ETH balance
      const ethBalanceAfter = await ethers.provider.getBalance(borrower.getAddress());
      expect(ethBalanceAfter).to.equal(ethBalanceBefore.sub(gasCost1).sub(gasCost2).sub(amount.mul(2)));

      // Check collateral balance
      const expectedCollateralBalance1 = underlyingToCToken(amount, exchangeRate1);
      const expectedCollateralBalance2 = underlyingToCToken(amount, exchangeRate2);
      const expectedCollateralBalance = expectedCollateralBalance1.add(expectedCollateralBalance2);
      expect(await cEthToken.balanceOf(compoundModule.address)).to.equal(expectedCollateralBalance);
      expect(await compoundModule.collateralBalanceOf(borrower.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should not be able to borrow if no collateral provided", async () => {
      // TODO: fix issue in SC when borrowing too low values
      await expect(compoundModule.connect(borrower).borrow(1)).to.be.revertedWith("Borrowing is too low.");
    });

    it("Should be able to borrow on Compound after providing collateral up to max", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const collateralBalanceInCEth = await compoundModule.collateralBalanceOf(borrower.getAddress());
      const cEthExchangeRate = await cEthToken.exchangeRateStored();
      const collateralBalanceInEth = cTokenToUnderlying(collateralBalanceInCEth, cEthExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const ethPriceMantissa = await compoundOracle.getUnderlyingPrice(CETH_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInEth.mul(ethPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

      await compoundModule.connect(borrower).borrow(maxToBorrow);

      // All underlyings should have been sent to the borrower
      const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
    });

    it("Should not be able to borrow more than max allowed given an amount of collateral", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const collateralBalanceInCEth = await compoundModule.collateralBalanceOf(borrower.getAddress());
      const cEthExchangeRate = await cEthToken.exchangeRateStored();
      const collateralBalanceInEth = cTokenToUnderlying(collateralBalanceInCEth, cEthExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const ethPriceMantissa = await compoundOracle.getUnderlyingPrice(CETH_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInEth.mul(collateralFactorMantissa).div(daiPriceMantissa).mul(ethPriceMantissa).div(SCALE);
      const moreThanMaxToBorrow = maxToBorrow.add(utils.parseUnits("0.0001"));

      // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
      await expect(compoundModule.connect(borrower).borrow(moreThanMaxToBorrow)).to.be.revertedWith("Not enough collateral.");
    });
  })

  describe("Check P2P interactions", () => {
    it("Lender should withdraw her liquidity while not enough cToken on Morpho contract", async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits("10");
      const daiBalanceBefore1 = await daiToken.balanceOf(lender.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(lendingAmount);
      await daiToken.connect(lender).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender).lend(lendingAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cToken.exchangeRateStored();
      const expectedLendingBalanceOnComp1 = underlyingToCToken(lendingAmount, cExchangeRate1);
      expect(await cToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp1);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp1);

      // Borrower provides collateral
      const collateralAmount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: collateralAmount });

      // Borrowers borrows lender amount
      await compoundModule.connect(borrower).borrow(lendingAmount);

      // Check lender balances
      const cExchangeRate2 = await cToken.exchangeRateStored();
      const mExchangeRate1 = await compoundModule.currentExchangeRate();
      const expectedLendingBalanceOnComp2 = expectedLendingBalanceOnComp1.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceOf(lender.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Check lending balance balances
      const cExchangeRate3 = await cToken.exchangeRateStored();
      await compoundModule.connect(owner).updateCurrentExchangeRate();
      const mExchangeRate2 = await compoundModule.currentExchangeRate();
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await compoundModule.BPY(), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender.getAddress());
      const lendingBalanceOnComp3 = (await compoundModule.lendingBalanceOf(lender.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho;
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cToken.balanceOf(compoundModule.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.gt(cTokenContractBalanceInUnderlying);
      const expectedMorphoBorrowingBalance = remainingToWithdraw.add(cTokenContractBalanceInUnderlying).sub(lendingBalanceOnCompInUnderlying);
      const expectedBorrowingBalanceOnComp = expectedMorphoBorrowingBalance;

      // Withdraw
      await compoundModule.connect(lender).withdraw(amountToWithdraw);
      const borrowBalance = await cToken.borrowBalanceStored(compoundModule.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender.getAddress());

      // Check borrow balance of Morpho
      expect(removeDigitsBigNumber(borrowBalance)).to.equal(removeDigitsBigNumber(expectedMorphoBorrowingBalance));

      // Check lender token balance
      expect(removeDigitsBigNumber(daiBalanceAfter2)).to.equal(removeDigitsBigNumber(expectedDaiBalanceAfter2));

      // Check lending balances of lender
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(0);
      expect(removeDigitsBigNumber((await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho)).to.equal(0);

      // Check borrowing balances of borrower
      expect(removeDigitsBigNumber((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onComp)).to.equal(removeDigitsBigNumber(expectedBorrowingBalanceOnComp));
      expect(removeDigitsBigNumber((await compoundModule.borrowingBalanceOf(borrower.getAddress())).onMorpho)).to.equal(0);
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

    it("Should be subjected to Oracle Manipulation attacs", async () => {
    });
  });
});