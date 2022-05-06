/* eslint-disable no-console */
const config = require(`@config/${process.env.NETWORK}-config.json`);
import hre, { ethers, upgrades } from 'hardhat';

// Check this doc to understand how the OZ upgrade plugin works: https://docs.openzeppelin.com/upgrades-plugins/1.x/

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('\n🦋 Deploying Morpho contracts for Compound');
  console.log('👩 Deployer account:', deployer.address);
  console.log('🤑 Account balance:', (await deployer.getBalance()).toString());

  /// INTEREST RATES DEPLOYMENT ///

  console.log('\n🦋 Deploying InterestRates...');
  const InterestRates = await ethers.getContractFactory('InterestRates');
  const interestRates = await InterestRates.deploy();
  await interestRates.deployed();
  console.log('🎉 InterestRates deployed to address:', interestRates.address);

  console.log('\n🦋 Verifying InterestRates on Tenderly...');
  await hre.tenderly.verify({
    name: 'InterestRates',
    address: interestRates.address,
  });
  console.log('🎉 InterestRates verified!');

  /// POSITIONS MANAGER DEPLOYMENT ///

  console.log('\n🦋 Deploying PositionsManager...');
  const PositionsManager = await ethers.getContractFactory('PositionsManager');
  const positionsManager = await PositionsManager.deploy();
  await positionsManager.deployed();
  console.log('🎉 PositionsManager deployed to address:', positionsManager.address);

  console.log('\n🦋 Verifying PositionsManager on Tenderly...');
  await hre.tenderly.verify({
    name: 'PositionsManager',
    address: positionsManager.address,
  });
  console.log('🎉 PositionsManager verified!');

  /// MORPHO DEPLOYMENT ///

  const maxGas = { supply: 3e6, borrow: 3e6, withdraw: 3e6, repay: 3e6 };

  console.log('\n🦋 Deploying Morpho...');
  const Morpho = await ethers.getContractFactory('Morpho');
  const morpho = await upgrades.deployProxy(
    Morpho,
    [
      positionsManager.address,
      interestRates.address,
      config.compound.comptroller.address,
      1,
      maxGas,
      100,
      config.tokens.cEth.address,
      config.tokens.wEth.address,
    ],
    { unsafeAllow: ['delegatecall'] }
  );
  await morpho.deployed();
  const morphoImplementationAddress = await upgrades.erc1967.getImplementationAddress(morpho.address);

  console.log('🎉 Morpho Proxy deployed to address:', morpho.address);
  console.log('🎉 Morpho Implementation deployed to address:', morphoImplementationAddress);

  console.log('\n🦋 Verifying Morpho Proxy on Tenderly...');
  await hre.tenderly.verify({
    name: 'Morpho Proxy',
    address: morpho.address,
  });
  console.log('🎉 Morpho Proxy verified!');

  console.log('\n🦋 Verifying Morpho Implementation on Tenderly...');
  await hre.tenderly.verify({
    name: 'Morpho Implementation',
    address: morphoImplementationAddress,
  });
  console.log('🎉 Morpho Implementation verified!');

  /// MARKETS CREATION ///

  console.log('\n🦋 Creating markets...');
  await morpho.connect(deployer).createMarket(config.tokens.cEth.address);
  await morpho.connect(deployer).createMarket(config.tokens.cDai.address);
  await morpho.connect(deployer).createMarket(config.tokens.cUsdc.address);
  console.log('🎉 Finished!\n');

  // TODO: Deploy incentives vault, rewards manager if possible.
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
