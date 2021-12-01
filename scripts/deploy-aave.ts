/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const RedBlackBinaryTree = await ethers.getContractFactory('contracts/aave/libraries/RedBlackBinaryTree.sol:RedBlackBinaryTree');
  const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
  await redBlackBinaryTree.deployed();

  console.log('RedBlackBinaryTree address:', redBlackBinaryTree.address);

  const UpdatePositions = await ethers.getContractFactory('contracts/aave/UpdatePositions.sol:UpdatePositions', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const updatePositions = await UpdatePositions.deploy();
  await updatePositions.deployed();

  const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
  const marketsManagerForAave = await MarketsManagerForAave.deploy();
  await marketsManagerForAave.deployed();

  console.log('MarketsManagerForAave address:', marketsManagerForAave.address);

  const PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const positionsManagerForAave = await PositionsManagerForAave.deploy(
    marketsManagerForAave.address,
    config.compound.comptroller.address,
    updatePositions.address
  );
  await positionsManagerForAave.deployed();

  console.log('PositionsManagerForAave address:', positionsManagerForAave.address);

  await marketsManagerForAave.connect(deployer).setPositionsManager(positionsManagerForAave.address);
  await marketsManagerForAave.connect(deployer).createMarket(config.tokens.cDai.address, BigNumber.from(1).pow(6));
  await marketsManagerForAave.connect(deployer).createMarket(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
