import { expect } from "chai";
import hre from "hardhat";

import { MorphoAaveV2__factory } from "@morpho-labs/morpho-ethers-contract";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

import "../../hardhat.config";

import WadRayMath from "./maths/WadRayMath";
import { data, markets } from "./mocks/aave-v2.json";

const market = "0x1982b2F5814301d4e9a8b0201555376e62F82428".toLowerCase();

describe("Check ugprade", () => {
  let snapshotId: number;

  const morpho = MorphoAaveV2__factory.connect("0x777777c9898d384f785ee44acfe945efdff5f3e0", hre.ethers.provider);

  const deployUpgrade = async () => {
    const InterestRatesManagerUpgraded = await hre.ethers.getContractFactory("InterestRatesManagerUpgraded");

    const interestRatesManagerUpgraded = await InterestRatesManagerUpgraded.deploy();
    await interestRatesManagerUpgraded.deployed();

    const owner = await hre.ethers.provider.getSigner(await morpho.owner());
    await morpho.connect(owner).setInterestRatesManager(interestRatesManagerUpgraded.address);
  };

  beforeEach(async () => {
    snapshotId = await hre.network.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await hre.network.provider.send("evm_revert", [snapshotId]);
  });

  it("should withdraw reasonable amount", async () => {
    loadFixture(deployUpgrade);

    for (const [user, userBalances] of Object.entries(data.users)) {
      if (!userBalances.positions[market]) continue;

      console.log("Impersonating", user);
      await hre.network.provider.request({
        method: "hardhat_setBalance",
        params: [user, "0xffffffffffffffffffffffffffffffffffffff"],
      });
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [user],
      });

      const amount = WadRayMath.rayMul(userBalances.positions[market].supply.onPool, markets[market].indexes.poolSupply).add(
        WadRayMath.rayMul(userBalances.positions[market].supply.inP2P, markets[market].indexes.p2pSupply)
      );
      if (amount.eq(0)) continue;

      const stEth = await hre.ethers.getContractAt(
        ["function balanceOf(address) external view returns (uint256)"],
        "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
        await hre.ethers.provider.getSigner(user)
      );

      const balanceBefore = await stEth.balanceOf(user);

      await morpho.connect(stEth.signer).withdraw(market, amount, { gasLimit: 3_000_000 });

      const balanceAfter = await stEth.balanceOf(user);

      expect(balanceAfter.sub(balanceBefore).sub(amount).abs().lt(10)).to.be.true;

      await expect(morpho.connect(stEth.signer).withdraw(market, 1_000_000, { gasLimit: 3_000_000 })).to.be.reverted;

      const supplyBalance = await morpho.supplyBalanceInOf(user, market);
      expect(supplyBalance.onPool.toString()).to.eq("0");
      expect(supplyBalance.inP2P.toString()).to.eq("0");
    }
  });
});
