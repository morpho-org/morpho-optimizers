import { expect } from "chai";
import { BigNumber } from "ethers";
import hre from "hardhat";

import { MorphoAaveV2__factory } from "@morpho-labs/morpho-ethers-contract";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

import "../../hardhat.config";

import WadRayMath from "./maths/WadRayMath";
import mock from "./mocks/aave-v2.15580517.json";

interface UserMarketBalance {
  onPool: string;
  inP2P: string;
  since: {
    blockNumber: number;
    transactionIndex: number;
  };
}

const data: {
  users: {
    [user: string]: {
      balances: {
        [market: string]: {
          supply?: UserMarketBalance;
          borrow?: UserMarketBalance;
        };
      };
    };
  };
} = mock.data;
const markets: {
  [market: string]: {
    price: string;
    indexes: {
      poolSupply: string;
      p2pSupply: string;
      poolBorrow: string;
      p2pBorrow: string;
    };
  };
} = mock.markets;

const aStEth = "0x1982b2F5814301d4e9a8b0201555376e62F82428".toLowerCase();

describe("Check ugprade", () => {
  let snapshotId: number;

  const morpho = MorphoAaveV2__factory.connect("0x777777c9898d384f785ee44acfe945efdff5f3e0", hre.ethers.provider);

  const deployUpgrade = async () => {
    const InterestRatesManagerUpgraded = await hre.ethers.getContractFactory("src/aave-v2/InterestRatesManager.sol:InterestRatesManager");

    const interestRatesManagerUpgraded = await InterestRatesManagerUpgraded.deploy();
    await interestRatesManagerUpgraded.deployed();

    const ownerAddress = await morpho.owner();
    await hre.network.provider.request({
      method: "hardhat_setBalance",
      params: [ownerAddress, "0xffffffffffffffffffffffffffffffffffffff"],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ownerAddress],
    });
    const owner = await hre.ethers.provider.getSigner(ownerAddress);
    await morpho.connect(owner).setInterestRatesManager(interestRatesManagerUpgraded.address);
  };

  beforeEach(async () => {
    snapshotId = await hre.network.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await hre.network.provider.send("evm_revert", [snapshotId]);
  });

  it("should withdraw reasonable amount", async () => {
    await loadFixture(deployUpgrade);

    for (const [user, userBalances] of Object.entries(data.users)) {
      const userMarketBalances = userBalances.balances[aStEth];
      if (
        !userMarketBalances ||
        !userMarketBalances.supply ||
        BigNumber.from(userMarketBalances.supply.onPool).add(userMarketBalances.supply.inP2P).lte(0)
      )
        continue;

      console.log("Impersonating", user);
      await hre.network.provider.request({
        method: "hardhat_setBalance",
        params: [user, "0xffffffffffffffffffffffffffffffffffffff"],
      });
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [user],
      });

      const amount = WadRayMath.rayMul(userMarketBalances.supply.onPool, markets[aStEth].indexes.poolSupply).add(
        WadRayMath.rayMul(userMarketBalances.supply.inP2P, markets[aStEth].indexes.p2pSupply)
      );
      if (amount.eq(0)) continue;

      const signer = await hre.ethers.provider.getSigner(user);
      const stEth = await hre.ethers.getContractAt(
        ["function balanceOf(address) external view returns (uint256)"],
        "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
        signer
      );

      const balanceBefore = await stEth.balanceOf(user);

      await morpho.connect(signer).withdraw(aStEth, amount, { gasLimit: 3_000_000 });

      const balanceAfter = await stEth.balanceOf(user);

      expect(balanceAfter.sub(balanceBefore).sub(amount).abs().lt(10)).to.be.true;

      await expect(morpho.connect(signer).withdraw(aStEth, 1_000, { gasLimit: 3_000_000 })).to.be.reverted;

      const supplyBalance = await morpho.supplyBalanceInOf(user, aStEth);
      expect(supplyBalance.onPool.toString()).to.eq("0");
      expect(supplyBalance.inP2P.toString()).to.eq("0");
    }
  });
});
