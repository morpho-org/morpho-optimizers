/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import hre, { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  if (process.env.NETWORK == 'mainnet') {
    await hre.network.provider.send('hardhat_setBalance', [deployer.address, '0x100000000000000000000000000']);
  }

  console.log('\n🦋 Deploying Morpho contracts for Compound');
  console.log('👩 Deployer account:', deployer.address);
  console.log('🤑 Account balance:', (await deployer.getBalance()).toString());

  /// INTEREST RATES MANAGER DEPLOYMENT ///

  console.log('\n🦋 Deploying InterestRatesManager...');
  const InterestRatesManager = await ethers.getContractFactory('InterestRatesManager');
  const interestRatesManager = await InterestRatesManager.deploy();
  await interestRatesManager.deployed();
  console.log('🎉 InterestRatesManager deployed to address:', interestRatesManager.address);

  console.log('\n🦋 Verifying InterestRatesManager on Tenderly...');
  await hre.tenderly.verify({
    name: 'InterestRatesManager',
    address: interestRatesManager.address,
  });
  console.log('🎉 InterestRatesManager verified!');

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
      interestRatesManager.address,
      config.compound.comptroller.address,
      maxGas,
      1,
      100,
      config.tokens.cEth.address,
      config.tokens.wEth.address,
    ],
    { unsafeAllow: ['delegatecall'] }
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
