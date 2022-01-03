/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import hre, { ethers, upgrades } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('\n🦋 Deploying Morpho contracts for Aave');
  console.log('👩 Deployer account:', await deployer.getAddress());
  console.log('🤑 Account balance:', (await deployer.getBalance()).toString());

  console.log('\n🦋 Deploying MarketsManagerForAave...');
  const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
  const marketsManagerForAave = await MarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
  await marketsManagerForAave.deployed();

  await marketsManagerForAave.connect(deployer).updateLendingPool();
  console.log('🎉 MarketsManagerForAave deployed to address:', marketsManagerForAave.address);

  console.log('\n🦋 Verifying MarketsManagerForAave on Tenderly...');
  await hre.tenderly.verify({
    name: 'MarketsManagerForAave',
    address: marketsManagerForAave.address,
  });
  console.log('🎉 MarketsManagerForAave verified!');

  console.log('\n🦋 Deploying PositionsManagerForAave...');
  const PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave');
  const positionsManagerForAave = await PositionsManagerForAave.deploy(
    marketsManagerForAave.address,
    config.aave.lendingPoolAddressesProvider.address
  );
  await positionsManagerForAave.deployed();
  console.log('🎉 PositionsManagerForAave deployed to address:', positionsManagerForAave.address);

  console.log('\n🦋 Verifying PositionsManagerForAave on Tenderly...');
  await hre.tenderly.verify({
    name: 'PositionsManagerForAave',
    address: positionsManagerForAave.address,
  });
  console.log('🎉 PositionsManagerForAave verified!');

  console.log('\n🦋 Deploying PositionsUpdator...');
  const PositionsUpdator = await ethers.getContractFactory('PositionsUpdatorV1');
  const positionsUpdatorProxy = await upgrades.deployProxy(PositionsUpdator, [positionsManagerForAave.address], {
    kind: 'uups',
    unsafeAllow: ['delegatecall'],
  });
  await positionsUpdatorProxy.deployed();
  console.log('🎉 PositionsUpdator Proxy deployed to address:', positionsUpdatorProxy.address);

  // Set proxy
  await marketsManagerForAave.updatePositionsUpdator(positionsUpdatorProxy.address);
  await marketsManagerForAave.updateMaxIterations(20);

  console.log('\n🦋 Creating markets...');
  const defaultThreshold = BigNumber.from(10).pow(6);
  const defaultCapValue = BigNumber.from(2);

  await marketsManagerForAave.connect(deployer).createMarket(config.tokens.aDai.address, defaultThreshold, defaultCapValue);
  await marketsManagerForAave.connect(deployer).createMarket(config.tokens.aUsdc.address, defaultThreshold, defaultCapValue);
  console.log('🎉 Finished!\n');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
