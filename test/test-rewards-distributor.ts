import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import hre, { ethers } from 'hardhat';
import { MerkleTree } from 'merkletreejs';
import { Signer, Contract } from 'ethers';
import { expect } from 'chai';

describe('RewardsDistributor Contract', () => {
  let snapshotId: number;
  let rewardsDistributor: Contract;
  let governance: Signer;
  let account0: Signer;
  let account1: Signer;
  let account2: Signer;
  const tokens: Contract[] = [];
  let distribution: any[];
  const tokensSetup = [
    { name: 'token0', symbol: 'TOKEN0' },
    { name: 'token1', symbol: 'TOKEN1' },
    { name: 'token2', symbol: 'TOKEN2' },
  ];
  let proofs: any[];
  let leaves: any[];
  let root: string;
  let merkleTree: MerkleTree;
  const amount0 = ethers.utils.parseUnits('1');
  const amount1 = ethers.utils.parseUnits('1');
  const amount2 = ethers.utils.parseUnits('2');

  const initialize = async () => {
    const signers = await ethers.getSigners();
    [governance, account0, account1, account2] = signers;

    // Deploy RewardsDistributor
    const RewardsDistributor = await ethers.getContractFactory('RewardsDistributor');
    rewardsDistributor = await RewardsDistributor.deploy();
    await rewardsDistributor.deployed();

    const FakeToken = await ethers.getContractFactory('FakeToken');
    for (const i in tokensSetup) {
      const fakeToken = await FakeToken.deploy(tokensSetup[i].name, tokensSetup[i].symbol, rewardsDistributor.address);
      tokens.push(fakeToken);
    }

    distribution = [
      { account: await account0.getAddress(), token: tokens[0].address, claimable: amount0 },
      { account: await account0.getAddress(), token: tokens[1].address, claimable: amount0 },
      { account: await account1.getAddress(), token: tokens[1].address, claimable: amount1 },
      { account: await account2.getAddress(), token: tokens[2].address, claimable: amount2 },
    ];

    leaves = distribution.map((receiver) =>
      ethers.utils.solidityKeccak256(['address', 'address', 'uint256'], [receiver.account, receiver.token, receiver.claimable])
    );
    merkleTree = new MerkleTree(leaves, ethers.utils.keccak256, { sortPairs: true });
    proofs = distribution.map((receiver) => ({
      address: receiver.account,
      proof: merkleTree.getHexProof(
        ethers.utils.solidityKeccak256(['address', 'address', 'uint256'], [receiver.account, receiver.token, receiver.claimable])
      ),
    }));
    root = merkleTree.getHexRoot();
  };

  before(initialize);

  beforeEach(async () => {
    snapshotId = await hre.network.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await hre.network.provider.send('evm_revert', [snapshotId]);
  });

  describe('Test RewardsDistributor', () => {
    it('Only governance should be able to update root', async () => {
      const newRoot = ethers.utils.formatBytes32String('root');
      expect(rewardsDistributor.connect(account0).updateRoot(newRoot)).to.be.reverted;

      await rewardsDistributor.connect(governance).updateRoot(newRoot);
      expect(await rewardsDistributor.currRoot()).equal(newRoot);
    });

    it('Should claim nothing when no root', async () => {
      expect(
        rewardsDistributor
          .connect(account0)
          .claim(distribution[0].account, distribution[0].token, distribution[0].claimable, proofs[0].proof)
      ).to.be.reverted;
    });

    it('Should distribute various tokens on current distribution', async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);

      await rewardsDistributor
        .connect(account0)
        .claim(distribution[0].account, distribution[0].token, distribution[0].claimable, proofs[0].proof);
      await rewardsDistributor
        .connect(account0)
        .claim(distribution[1].account, distribution[1].token, distribution[1].claimable, proofs[1].proof);
      await rewardsDistributor
        .connect(account0)
        .claim(distribution[2].account, distribution[2].token, distribution[2].claimable, proofs[2].proof);
      await rewardsDistributor
        .connect(account0)
        .claim(distribution[3].account, distribution[3].token, distribution[3].claimable, proofs[3].proof);

      expect(await tokens[0].balanceOf(distribution[0].account)).to.equal(distribution[0].claimable);
      expect(await tokens[1].balanceOf(distribution[1].account)).to.equal(distribution[1].claimable);
      expect(await tokens[1].balanceOf(distribution[2].account)).to.equal(distribution[2].claimable);
      expect(await tokens[2].balanceOf(distribution[3].account)).to.equal(distribution[3].claimable);
    });

    it('Should not distribute for invalid tokens', async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);

      expect(
        rewardsDistributor
          .connect(account0)
          .claim(distribution[0].account, distribution[0].token, distribution[0].claimable, [
            ethers.utils.formatBytes32String('wrong root'),
          ])
      ).to.be.reverted;
    });

    it('Should not be possible to replay proof', async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);

      await rewardsDistributor
        .connect(account0)
        .claim(distribution[0].account, distribution[0].token, distribution[0].claimable, proofs[0].proof);

      expect(
        rewardsDistributor
          .connect(account0)
          .claim(distribution[0].account, distribution[0].token, distribution[0].claimable, proofs[0].proof)
      ).to.be.reverted;
    });

    it('Should be possible to claim for previous distribution', async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);
      await rewardsDistributor.connect(governance).updateRoot(ethers.utils.formatBytes32String('new root'));

      await rewardsDistributor
        .connect(account0)
        .claim(distribution[0].account, distribution[0].token, distribution[0].claimable, proofs[0].proof);
      expect(await tokens[0].balanceOf(distribution[0].account)).to.equal(distribution[0].claimable);
    });

    it('Should be possible to claim for previous and current distribution', async () => {
      await rewardsDistributor.connect(governance).updateRoot(root);

      const newDistribution = [{ account: await account0.getAddress(), token: tokens[0].address, claimable: amount0.add(amount1) }];
      const newLeaves = newDistribution.map((receiver) =>
        ethers.utils.solidityKeccak256(['address', 'address', 'uint256'], [receiver.account, receiver.token, receiver.claimable])
      );
      const newMerkleTree = new MerkleTree(newLeaves, ethers.utils.keccak256, { sortPairs: true });
      const newProofs = newDistribution.map((receiver) => {
        return {
          address: receiver.account,
          proof: newMerkleTree.getHexProof(
            ethers.utils.solidityKeccak256(['address', 'address', 'uint256'], [receiver.account, receiver.token, receiver.claimable])
          ),
        };
      });
      const newRoot = newMerkleTree.getHexRoot();

      await rewardsDistributor.connect(governance).updateRoot(newRoot);

      await rewardsDistributor
        .connect(account0)
        .claim(distribution[0].account, distribution[0].token, distribution[0].claimable, proofs[0].proof);
      await rewardsDistributor
        .connect(account0)
        .claim(newDistribution[0].account, newDistribution[0].token, newDistribution[0].claimable, newProofs[0].proof);
      expect(await tokens[0].balanceOf(distribution[0].account)).to.equal(newDistribution[0].claimable);
    });
  });
});
