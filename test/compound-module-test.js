const { expect } = require("chai");
const hre = require("hardhat");
const { utils, BigNumber } = require('ethers');
const daiAbi = require('./abis/dai-abi.json');

describe("CompoundModuleETH Contract", () => {

  const WETH_ADDRESS = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";
  const CETH_ADDRESS = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
  const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const CDAI_ADDRESS = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643";
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

  const underlyingToCToken = (amount, exchangeRateCurrent, underlyingDecimals) => {
    const mantissa = 18 + parseInt(underlyingDecimals) - cTokenDecimals;
    return amount * BigNumber.from(10).pow(mantissa) / exchangeRateCurrent;
  }

  const cTokenToUnderlying = (amount, exchangeRateCurrent, underlyingDecimals) => {
    const mantissa = 18 + parseInt(underlyingDecimals) - cTokenDecimals;
    return amount * exchangeRateCurrent / BigNumber.from(10).pow(mantissa);
  }

  beforeEach(async () => {
    // CompoundModule
    CompoundModule = await ethers.getContractFactory("CompoundModuleETH");
    [lender, borrower, owner, ...addrs] = await ethers.getSigners();
    compoundModule = await CompoundModule.deploy();
    await compoundModule.deployed();

    cEthToken = await ethers.getContractAt("ICEth", CETH_ADDRESS, owner);
    cDaiToken = await ethers.getContractAt("ICErc20", CDAI_ADDRESS, owner);
    const daiMcdJoin = '0x9759A6Ac90977b93B58547b4A71c78317f391A28';
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [daiMcdJoin],
    });
    const daiSigner = await ethers.getSigner(daiMcdJoin)
    daiToken = await ethers.getContractAt(daiAbi, DAI_ADDRESS, daiSigner);

    // Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
    const daiAmount = utils.parseUnits("10000");
    const ethAmount = utils.parseUnits("100");
    await network.provider.send("hardhat_setBalance", [
      daiMcdJoin,
      utils.hexValue(ethAmount),
    ]);
    await daiToken.mint(lender.getAddress(), daiAmount, { from: daiMcdJoin });
    console.log((await daiToken.balanceOf(lender.getAddress())).toString());
  });

  describe("Deployment", () => {
    it("Should deploy the contract", async () => {
      expect(await compoundModule.collateralFactor()).to.equal("750000000000000000");
      expect(await compoundModule.liquidationIncentive()).to.equal("8000");
      expect(await compoundModule.DENOMINATOR()).to.equal("10000");
    });
  });

  // lend
  describe("Lend function when there is no borrowers", () => {
    it("Should have correct balances at the beginning", async () => {
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho).to.equal(0);
    })

    it("Should revert with amount 0", async () => {
      await expect(compoundModule.connect(lender).lend(0)).to.be.revertedWith("Amount cannot be 0");
    })

    it("Should have the right amount of cETH in onComp lending balance after", async () => {
      const amount = utils.parseUnits("10");
      await daiToken.connect(lender).approve(compoundModule.address, 10);
      await compoundModule.connect(lender).lend(10);
      console.log(await daiToken.balanceOf(compoundModule.address));
      exchangeRateCurrent = await cDaiToken.exchangeRateCurrent();
      // const expectedLendingBalanceOnMorpho = underlyingToCToken(amount, exchangeRateCurrent, 18);
      // expect(Number((await compoundModule.lendingBalanceOf(lender.getAddress())).onMorpho)).to.equal(expectedLendingBalanceOnMorpho);
    })

    it("Should have the right amount of ETH in onMorpho lending balance after", async () => {
      const ethAmount = utils.parseUnits("1");
      compoundModule.lend({ from: owner.getAddress(), value: ethAmount });
      const expectedLendingBalanceOnMorpho = 0;
      expect((await compoundModule.lendingBalanceOf(owner.getAddress())).onMorpho).to.equal(expectedOnMorphoLendingBalance);
    })

    // it("Should should have the correct amount of ETH on Compound after", async () => {
    // })
  })

  // describe("Lend function when there is not enough borrowers", () => {
  // })

  // describe("Lend function when there is enough borrowers", () => {
  // })

  // describe("Lending / Borrowing", () => {
  //   it("Should lend 1 ETH", async () => {
  //     const ethAmount = utils.parseUnits("1");
  //     const lenderBalanceBefore = await lender.getBalance(lender.getAddress());
  //     const compoundModuleCEthBalanceBefore = await cEthToken.balanceOf(compoundModule.getAddress());
  //     expect(compoundModuleCEthBalanceBefore).to.equal(0);
  //     await compoundModule.lend({ from: lender, value: ethAmount });
  //     const lenderBalanceAfter = await lender.getBalance(lender.getAddress());
  //     expect(BigNumber.from(lenderBalanceAfter)).to.equal(BigNumber.from(lenderBalanceBefore).add(ethAmount));
  //   });
  // });
});