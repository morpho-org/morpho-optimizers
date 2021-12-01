/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const DoubleLinkedList = await ethers.getContractFactory('contracts/aave/libraries/DoubleLinkedList.sol:DoubleLinkedList');
  const doubleLinkedList = await DoubleLinkedList.deploy();
  await doubleLinkedList.deployed();

  console.log('DoubleLinkedList address:', doubleLinkedList.address);

  const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
  const marketsManagerForAave = await MarketsManagerForAave.deploy();
  await marketsManagerForAave.deployed();

  console.log('MarketsManagerForAave address:', marketsManagerForAave.address);

  const PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave');
  const positionsManagerForAave = await PositionsManagerForAave.deploy(marketsManagerForAave.address, config.compound.comptroller.address);
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
