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

describe("CompoundModuleETH Contract", () => {

  const CETH_ADDRESS = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
  const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const CDAI_ADDRESS = "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643";
  const PROXY_COMPTROLLER_ADDRESS = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";
  const COMPOUND_ORACLE_ADDRESS = "0x841616a5CBA946CF415Efe8a326A621A794D0f97";

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
    // Users
    [lender, borrower, owner, ...addrs] = await ethers.getSigners();

    // Deploy CompoundModule
    CompoundModule = await ethers.getContractFactory("CompoundModuleETH");
    compoundModule = await CompoundModule.deploy();
    await compoundModule.deployed();

    // Get contract dependencies
    cEthToken = await ethers.getContractAt(CEthABI, CETH_ADDRESS, owner);
    cDaiToken = await ethers.getContractAt(CErc20ABI, CDAI_ADDRESS, owner);
    comptroller = await ethers.getContractAt(comptrollerABI, PROXY_COMPTROLLER_ADDRESS, owner);
    compoundOracle = await ethers.getContractAt(compoundOracleABI, COMPOUND_ORACLE_ADDRESS, owner);

    // Mint some DAI
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
    await network.provider.send("hardhat_setBalance", [
      daiMinter,
      utils.hexValue(ethAmount),
    ]);
    await daiToken.mint(lender.getAddress(), daiAmount, { from: daiMinter });
  });

  describe("Deployment", () => {
    it("Should deploy the contract with the right values", async () => {
      expect(await compoundModule.collateralFactor()).to.equal("750000000000000000");
      expect(await compoundModule.liquidationIncentive()).to.equal("11000");
      expect(await compoundModule.DENOMINATOR()).to.equal("10000");

      // Calculate BPY
      const borrowRatePerBlock = await cDaiToken.borrowRatePerBlock();
      const supplyRatePerBlock = await cDaiToken.supplyRatePerBlock();
      const expectedBPY = borrowRatePerBlock.add(supplyRatePerBlock).div(2);
      expect(await compoundModule.BPY()).to.equal(expectedBPY);
    });
  });

  describe("Test utils functions", () => {
    it("Should give the right collateral required for different values", async () => {
      // Amounts
      const amount1 = utils.parseUnits("10");
      const amount2 = utils.parseUnits("0");
      const amount3 = utils.parseUnits("100000000000");

      // Query collateral and prices
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const ethPriceMantissa = await compoundOracle.getUnderlyingPrice(CETH_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);

      // Collateral & expected collaterals
      const collateralRequired1 = await compoundModule.getCollateralRequired(amount1, collateralFactorMantissa, CDAI_ADDRESS, CETH_ADDRESS);
      const collateralRequired2 = await compoundModule.getCollateralRequired(amount2, collateralFactorMantissa, CDAI_ADDRESS, CETH_ADDRESS);
      const collateralRequired3 = await compoundModule.getCollateralRequired(amount3, collateralFactorMantissa, CDAI_ADDRESS, CETH_ADDRESS);
      const expectedCollateralRequired1 = amount1.mul(daiPriceMantissa).mul(utils.parseUnits("1")).div(ethPriceMantissa).div(collateralFactorMantissa);
      const expectedCollateralRequired2 = amount2.mul(daiPriceMantissa).mul(utils.parseUnits("1")).div(ethPriceMantissa).div(collateralFactorMantissa);
      const expectedCollateralRequired3 = amount3.mul(daiPriceMantissa).mul(utils.parseUnits("1")).div(ethPriceMantissa).div(collateralFactorMantissa);

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

    // Note: this is not porrible to access the result off-chain as the function is not pure/view.
    // We should add en event to allow catching of the values.
    xit("Should give the right account liquidity for an empty account", async () => {
      const { collateralInEth, collateralRequiredInEth } = (await compoundModule.getAccountLiquidity(borrower.getAddress())).value;
      expect(collateralRequiredInEth).to.equal(0);
      expect(collateralInEth).to.equal(0);
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

    it("Should have the right amount of cDAI onComp after lending DAI", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(lender).approve(compoundModule.address, amount);
      await compoundModule.connect(lender).lend(amount);
      const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

      // Check dai balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const exchangeRate = await cDaiToken.exchangeRateStored();
      const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
    })

    it("Should be able to cash-out DAI right after lending up to max lending balance", async () => {
      const amount = utils.parseUnits("10");
      const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
      await daiToken.connect(lender).approve(compoundModule.address, amount);
      await compoundModule.connect(lender).lend(amount);
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceOf(lender.getAddress())).onComp;
      const exchangeRate1 = await cDaiToken.exchangeRateStored();
      const toCashOut1 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate1);

      // Check that lender cannot withdraw too much
      // TODO: improve this test to prevent attacks
      await expect(compoundModule.connect(lender).cashOut(toCashOut1.add(utils.parseUnits("0.001")).toString())).to.be.reverted;

      // To improve as there is still dust after withdrawing: create a function with cToken as input?
      // Update exchange rate
      await cDaiToken.connect(lender).exchangeRateCurrent();
      const exchangeRate2 = await cDaiToken.exchangeRateStored();
      const toCashOut2 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate2);
      await compoundModule.connect(lender).cashOut(toCashOut2);
      const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

      // Check DAI balance
      // expect(toCashOut2).to.be.above(toCashOut1);
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amount).add(toCashOut2));

      // Check cDAI left are only dust in lending balance
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.lt(1000);
      await expect(compoundModule.connect(lender).cashOut(utils.parseUnits("0.001"))).to.be.reverted;
    })

    it("Should be able to lend more DAI after already having lend DAI", async () => {
      const amount = utils.parseUnits("10");
      const amountToApprove = utils.parseUnits("10").mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());

      // Tx are done in different blocks.
      await daiToken.connect(lender).approve(compoundModule.address, amountToApprove);
      await compoundModule.connect(lender).lend(amount);
      const exchangeRate1 = await cDaiToken.exchangeRateStored();
      await compoundModule.connect(lender).lend(amount);
      const exchangeRate2 = await cDaiToken.exchangeRateStored();

      // Check DAI balance
      const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check lending balance
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
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
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const exchangeRate = await cEthToken.exchangeRateStored();
      const expectedCollateralBalance = underlyingToCToken(amount, exchangeRate);
      expect(await compoundModule.collateralBalanceOf(borrower.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should be able to provide more collateral right after having providing some", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const exchangeRate1 = await cEthToken.exchangeRateStored();
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const exchangeRate2 = await cEthToken.exchangeRateStored();
      const expectedCollateralBalance1 = underlyingToCToken(amount, exchangeRate1);
      const expectedCollateralBalance2 = underlyingToCToken(amount, exchangeRate2);
      const expectedCollateralBalance = expectedCollateralBalance1.add(expectedCollateralBalance2);
      expect(await cEthToken.balanceOf(compoundModule.address)).to.equal(expectedCollateralBalance);
      expect(await compoundModule.collateralBalanceOf(borrower.getAddress())).to.equal(expectedCollateralBalance);
    });

    it("Should not be able to borrow if no collateral provided", async () => {
      // TODO: fix issue in SC with borrow
      await expect(compoundModule.connect(borrower).borrow(1)).to.be.revertedWith("Borrowing is too low.");
    });

    xit("Should be able to borrow on Compound after providing collateral up to max", async () => {
      const amount = utils.parseUnits("10");
      await compoundModule.connect(borrower).provideCollateral({ value: amount });
      const collateralFactor = compoundModule.collateralFactor();
      const maxToBorrow = 0;
      await expect(compoundModule.connect(borrower).borrow(maxToBorrow)).to.be.revertedWith("Not enough collateral.");
    });

    xit("Should not be able to borrow more than max allowed given an amount of collateral", async () => {
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