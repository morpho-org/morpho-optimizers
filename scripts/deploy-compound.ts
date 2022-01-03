/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import hre, { ethers, upgrades } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('\n🦋 Deploying Morpho contracts for Compound');
  console.log('👩 Deployer account:', deployer.address);
  console.log('🤑 Account balance:', (await deployer.getBalance()).toString());

  console.log('\n🦋 Deploying MarketsManagerForCompound...');
  const MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
  const marketsManagerForCompound = await MarketsManagerForCompound.deploy(config.compound.comptroller.address);
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
  await positionsManagerForCompound.deployed();
  console.log('🎉 PositionsManagerForCompound deployed to address:', positionsManagerForCompound.address);

  console.log('\n🦋 Verifying PositionsManagerForCompound on Tenderly...');
  await hre.tenderly.verify({
    name: 'PositionsManagerForCompound',
    address: positionsManagerForCompound.address,
  });
  console.log('🎉 PositionsManagerForCompound verified!');

  console.log('\n🦋 Deploying PositionsUpdator...');
  const PositionsUpdator = await ethers.getContractFactory('PositionsUpdatorV1');
  const positionsUpdatorProxy = await upgrades.deployProxy(PositionsUpdator, [positionsManagerForCompound.address], {
    kind: 'uups',
    unsafeAllow: ['delegatecall'],
  });
  await positionsUpdatorProxy.deployed();
  console.log('🎉 PositionsUpdator Proxy deployed to address:', positionsUpdatorProxy.address);

  // Set proxy
  await marketsManagerForCompound.updatePositionsUpdator(positionsUpdatorProxy.address);
  await marketsManagerForCompound.updateMaxIterations(20);

  console.log('\n🦋 Creating markets...');
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
