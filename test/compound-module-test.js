const { expect } = require("chai");
const { utils, BigNumber } = require('ethers');
const cEthJson = require('../artifacts/contracts/interfaces/ICompound.sol/ICEth.json');


describe("CompoundModule Contract", () => {

  const WETH_ADDRESS = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
  const CETH_ADDRESS = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
  const DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  const CDAI_ADDRESS = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
  const COMPOUND_ORACLE_ADDRESS = 0x841616a5CBA946CF415Efe8a326A621A794D0f97;

  let cEthToken;
  let cDaiToken;
  let daiToken;
  let CompoundModule;
  let compoundModule;
  let lender;
  let borrower;

  beforeEach(async () => {
    CompoundModule = await ethers.getContractFactory("CompoundModule");
    // CEth = await ethers.getContractFactory("ICEth");
    // CEth = await artifacts.readArtifact("ICEth");
    [lender, borrower] = await ethers.getSigners();
    compoundModule = await CompoundModule.deploy();
    await compoundModule.deployed();
    cEthToken = await ethers.getContractAt(cEthJson.abi, CETH_ADDRESS, lender);
  });

  describe("Deployment", () => {
    it("Should deploy the contract", async () => {
      expect(await compoundModule.collateralFactor()).to.equal("750000000000000000");
      expect(await compoundModule.liquidationIncentive()).to.equal("8000");
      expect(await compoundModule.DENOMINATOR()).to.equal("10000");
    });
  });

  describe("Lending / Borrowing", () => {
    it("Should lend 1 ETH", async () => {
      const ethAmount = utils.parseUnits("1");
      const lenderBalanceBefore = await lender.getBalance(lender.address);
      const compoundModuleCEthBalanceBefore = await cEthToken.balanceOf(compoundModule.address);
      expect(compoundModuleCEthBalanceBefore).to.equal(0);
      await compoundModule.lend({ from: lender, value: ethAmount });
      const lenderBalanceAfter = await lender.getBalance(lender.address);
      expect(BigNumber.from(lenderBalanceAfter)).to.equal(BigNumber.from(lenderBalanceBefore).add(ethAmount));
    });
  });
});