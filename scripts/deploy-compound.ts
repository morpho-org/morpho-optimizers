/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import hre, { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('\n🦋 Deploying Morpho contracts for Compound');
  console.log('👩 Deployer account:', deployer.address);
  console.log('🤑 Account balance:', (await deployer.getBalance()).toString());

  console.log('\n🦋 Deploying MarketsManagerForCompound...');
  const MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
  const marketsManagerForCompound = await MarketsManagerForCompound.deploy();
  await marketsManagerForCompound.deployed();
  console.log('🎉 MarketsManagerForCompound deployed to address:', marketsManagerForCompound.address);

  console.log('\n🦋 Verifying MarketsManagerForCompound on Tenderly...');
  await hre.tenderly.verify({
    name: 'MarketsManagerForCompound',
    address: marketsManagerForCompound.address,
  });
  console.log('🎉 PositionsManagerForCompound verified!');

  console.log('\n🦋 Deploying PositionsManagerForCompound...');
  const PositionsManagerForCompound = await ethers.getContractFactory('PositionsManagerForCompound');
  const positionsManagerForCompound = await PositionsManagerForCompound.deploy(
    marketsManagerForCompound.address,
    config.compound.comptroller.address
  );
  await morpho.deployed();
  const morphoImplementationAddress = await upgrades.erc1967.getImplementationAddress(morpho.address);

  console.log('\n🦋 Verifying PositionsManagerForCompound on Tenderly...');
  await hre.tenderly.verify({
    name: 'PositionsManagerForCompound',
    address: positionsManagerForCompound.address,
  });
  console.log('🎉 PositionsManagerForCompound verified!');

  console.log('\n🦋 Creating markets...');
  await marketsManagerForCompound.connect(deployer).setPositionsManager(positionsManagerForCompound.address);
  await marketsManagerForCompound.connect(deployer).createMarket(config.tokens.cDai.address, BigNumber.from(1).pow(6));
  await marketsManagerForCompound.connect(deployer).createMarket(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
  console.log('🎉 Finished!\n');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
