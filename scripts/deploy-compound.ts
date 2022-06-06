/* eslint-disable no-console */
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { CallOverrides } from 'ethers';
import hre from 'hardhat';

const MAX_HEX_AMOUNT = '0x' + 'f'.repeat(64);

const deploymentOptions: CallOverrides = {
  //   maxFeePerGas: BigNumber.from('30000000000'),
  //   maxPriorityFeePerGas: BigNumber.from('15000000000'),
};

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  if (hre.network.name === 'forkMainnet') {
    await hre.network.provider.send('hardhat_setBalance', [deployer.address, MAX_HEX_AMOUNT]);
  }

  console.log('\n🦋 Deploying Morpho contracts for Compound');
  console.log('👩 Deployer account:', deployer.address);

  /// INTEREST RATES MANAGER DEPLOYMENT ///

  console.log('\n🦋 Deploying InterestRatesManager...');
  const InterestRatesManager = await hre.ethers.getContractFactory('InterestRatesManager');
  const interestRatesManager = await InterestRatesManager.deploy(deploymentOptions);
  console.log('🕰️  Transaction:', interestRatesManager.deployTransaction.hash);
  await interestRatesManager.deployed();
  console.log('🎉 InterestRatesManager deployed at address:', interestRatesManager.address);
  //   const interestRatesManager = await hre.ethers.getContractAt('InterestRatesManager', '0xfe7339C130402fbd0239515206F47D3B744cB552');

  if (hre.network.name === 'forkMainnet') {
    console.log('\n🦋 Verifying InterestRatesManager on Tenderly...');
    await hre.tenderly.verify({
      name: 'InterestRatesManager',
      address: interestRatesManager.address,
    });
  }
  console.log('🎉 InterestRatesManager verified!');

  /// POSITIONS MANAGER DEPLOYMENT ///

  console.log('\n🦋 Deploying PositionsManager...');
  const PositionsManager = await hre.ethers.getContractFactory('PositionsManager');
  const positionsManager = await PositionsManager.deploy(deploymentOptions);
  await positionsManager.deployed();
  console.log('🎉 PositionsManager deployed at address:', positionsManager.address);

  if (hre.network.name === 'forkMainnet') {
    console.log('\n🦋 Verifying PositionsManager on Tenderly...');
    await hre.tenderly.verify({
      name: 'PositionsManager',
      address: positionsManager.address,
    });
  }
  console.log('🎉 PositionsManager verified!');

  /// MORPHO DEPLOYMENT ///

  const dustThreshold = 1;
  const maxSortedUsers = 16;
  const defaultMaxGasForMatching = { supply: 1e5, borrow: 1e5, withdraw: 1e5, repay: 1e5 };

  // Check this doc to understand how the OZ upgrade plugin works: https://docs.openzeppelin.com/upgrades-plugins/1.x/
  console.log('\n🦋 Deploying Morpho...');
  const Morpho = await hre.ethers.getContractFactory('Morpho');
  const morpho = await hre.upgrades.deployProxy(
    Morpho,
    [
      positionsManager.address,
      interestRatesManager.address,
      config.compound.comptroller.address,
      defaultMaxGasForMatching,
      dustThreshold,
      maxSortedUsers,
      config.tokens.cEth.address,
      config.tokens.wEth.address,
    ],
    { unsafeAllow: ['delegatecall', 'constructor'] }
  );
  await morpho.deployed();
  const morphoImplementationAddress = await hre.upgrades.erc1967.getImplementationAddress(morpho.address);

  console.log('🎉 Morpho contract deployed');
  console.log('                      with proxy at address:\t', morpho.address);
  console.log('             with implementation at address:\t', morphoImplementationAddress);

  if (hre.network.name === 'forkMainnet') {
    console.log('\n🦋 Verifying Morpho Proxy on Tenderly...');
    await hre.tenderly.verify({
      name: 'Morpho Proxy',
      address: morpho.address,
    });
  }
  console.log('🎉 Morpho Proxy verified!');

  if (hre.network.name === 'forkMainnet') {
    console.log('\n🦋 Verifying Morpho Implementation on Tenderly...');
    await hre.tenderly.verify({
      name: 'Morpho Implementation',
      address: morphoImplementationAddress,
    });
  }
  console.log('🎉 Morpho Implementation verified!');

  /// MARKETS CREATION ///

  console.log('\n🦋 Creating markets...');
  await morpho.connect(deployer).createMarket(config.tokens.cEth.address, {
    reserveFactor: 1500,
    p2pIndexCursor: 3333,
  });
  await morpho.connect(deployer).createMarket(config.tokens.cDai.address, {
    reserveFactor: 1500,
    p2pIndexCursor: 3333,
  });
  await morpho.connect(deployer).createMarket(config.tokens.cUsdc.address, {
    reserveFactor: 1500,
    p2pIndexCursor: 3333,
  });
  console.log('🎉 Finished!\n');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
