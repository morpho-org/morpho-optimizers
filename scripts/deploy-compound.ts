/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const DoubleLinkedList = await ethers.getContractFactory('contracts/compound/libraries/DoubleLinkedList.sol:DoubleLinkedList');
  const doubleLinkedList = await DoubleLinkedList.deploy();
  await doubleLinkedList.deployed();

  console.log('DoubleLinkedList address:', doubleLinkedList.address);

  const MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
  const marketsManagerForCompound = await MarketsManagerForCompound.deploy();
  await marketsManagerForCompound.deployed();

  console.log('MarketsManagerForCompound address:', marketsManagerForCompound.address);

  const PositionsManagerForCompound = await ethers.getContractFactory('PositionsManagerForCompound');
  const positionsManagerForCompound = await PositionsManagerForCompound.deploy(
    marketsManagerForCompound.address,
    config.compound.comptroller.address
  );
  await positionsManagerForCompound.deployed();

  console.log('PositionsManagerForCompound address:', positionsManagerForCompound.address);

  await marketsManagerForCompound.connect(deployer).setPositionsManager(positionsManagerForCompound.address);
  await marketsManagerForCompound.connect(deployer).createMarket(config.tokens.cDai.address, BigNumber.from(1).pow(6));
  await marketsManagerForCompound.connect(deployer).createMarket(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
