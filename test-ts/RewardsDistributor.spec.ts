import { expect } from "chai";
import { Signer, Contract } from "ethers";
import hre, { ethers } from "hardhat";
import { MerkleTree } from "merkletreejs";

import "../hardhat.config";

describe("RewardsDistributor Contract", () => {
  let snapshotId: number;
  let rewardsDistributor: Contract;
  let morphoToken: Contract;
  let governance: Signer;
  let account0: Signer;
  let account1: Signer;
  let account2: Signer;
  let distribution: any[];
  let proofs: any[];
  let leaves: any[];
  let root: string;
  let merkleTree: MerkleTree;
  const amount0 = ethers.utils.parseUnits("1");
  const amount1 = ethers.utils.parseUnits("1");
  const amount2 = ethers.utils.parseUnits("2");
  const amountMinted = ethers.utils.parseUnits("100000");

  const initialize = async () => {
    const signers = await ethers.getSigners();
    [governance, account0, account1, account2] = signers;

    const MorphoToken = await ethers.getContractFactory("FakeToken");
    morphoToken = await MorphoToken.deploy("Morpho Token", "MORPHO");

    // Deploy RewardsDistributor
    const RewardsDistributor = await ethers.getContractFactory("RewardsDistributor");
    rewardsDistributor = await RewardsDistributor.deploy(morphoToken.address);
    await rewardsDistributor.deployed();

    // Mint tokens to RewardsDistributor
    await morphoToken.mint(rewardsDistributor.address, amountMinted);

    distribution = [
      { account: await account0.getAddress(), claimable: amount0 },
      { account: await account1.getAddress(), claimable: amount1 },
      { account: await account2.getAddress(), claimable: amount2 },
    ];

    leaves = distribution.map((receiver) => ethers.utils.solidityKeccak256(["address", "uint256"], [receiver.account, receiver.claimable]));
    merkleTree = new MerkleTree(leaves, ethers.utils.keccak256, { sortPairs: true });
    proofs = distribution.map((receiver) => ({
      address: receiver.account,
      proof: merkleTree.getHexProof(ethers.utils.solidityKeccak256(["address", "uint256"], [receiver.account, receiver.claimable])),
    }));
    root = merkleTree.getHexRoot();
  };

  before(initialize);

  beforeEach(async () => {
    snapshotId = await hre.network.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await hre.network.provider.send("evm_revert", [snapshotId]);
  });

  describe("Test RewardsDistributor", () => {
    it("Should withdraw Morpho tokens", async () => {
      const toWithdraw = ethers.utils.parseUnits("4");
      await rewardsDistributor.connect(governance).withdrawMorphoTokens(account0.getAddress(), toWithdraw);

      expect(await morphoToken.balanceOf(rewardsDistributor.address)).equal(amountMinted.sub(toWithdraw));
      expect(await morphoToken.balanceOf(account0.getAddress())).equal(toWithdraw);
    });

    it("Should withdraw Morpho tokens", async () => {
      await rewardsDistributor.connect(governance).withdrawMorphoTokens(account0.getAddress(), ethers.constants.MaxUint256);

      expect(await morphoToken.balanceOf(rewardsDistributor.address)).equal(0);
      expect(await morphoToken.balanceOf(account0.getAddress())).equal(amountMinted);
    });

    it("Only governance should be able to update root", async () => {
      const newRoot = ethers.utils.formatBytes32String("root");
      expect(rewardsDistributor.connect(account0).updateRoot(newRoot)).to.be.reverted;

      await rewardsDistributor.connect(governance).updateRoot(newRoot);
      expect(await rewardsDistributor.currRoot()).equal(newRoot);
    });

    it("Should claim nothing when no root", async () => {
      expect(rewardsDistributor.connect(account0).claim(distribution[0].account, distribution[0].claimable, proofs[0].proof)).to.be
        .reverted;
    });

    it("Should not be possible to replay proof", async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);

      await rewardsDistributor.connect(account0).claim(distribution[0].account, distribution[0].claimable, proofs[0].proof);

      expect(rewardsDistributor.connect(account0).claim(distribution[0].account, distribution[0].claimable, proofs[0].proof)).to.be
        .reverted;
    });

    it("Should be possible to claim for previous distribution", async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);
      await rewardsDistributor.connect(governance).updateRoot(ethers.utils.formatBytes32String("new root"));

      await rewardsDistributor.connect(account0).claim(distribution[0].account, distribution[0].claimable, proofs[0].proof);
      expect(await morphoToken.balanceOf(distribution[0].account)).to.equal(distribution[0].claimable);
    });

    it("Should be possible to claim for previous and current distribution", async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);

      const newDistribution = [{ account: await account0.getAddress(), claimable: amount0.add(amount1) }];
      const newLeaves = newDistribution.map((receiver) =>
        ethers.utils.solidityKeccak256(["address", "uint256"], [receiver.account, receiver.claimable])
      );
      const newMerkleTree = new MerkleTree(newLeaves, ethers.utils.keccak256, { sortPairs: true });
      const newProofs = newDistribution.map((receiver) => {
        return {
          address: receiver.account,
          proof: newMerkleTree.getHexProof(ethers.utils.solidityKeccak256(["address", "uint256"], [receiver.account, receiver.claimable])),
        };
      });
      const newRoot = newMerkleTree.getHexRoot();

      await rewardsDistributor.connect(governance).updateRoot(newRoot);

      await rewardsDistributor.connect(account0).claim(distribution[0].account, distribution[0].claimable, proofs[0].proof);
      await rewardsDistributor.connect(account0).claim(newDistribution[0].account, newDistribution[0].claimable, newProofs[0].proof);
      expect(await morphoToken.balanceOf(distribution[0].account)).to.equal(newDistribution[0].claimable);
    });
  });
});
