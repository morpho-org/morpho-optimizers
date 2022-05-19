/* eslint-disable no-console */
import { formatEther } from 'ethers/lib/utils';

const config = require(`@config/${process.env.NETWORK}-config.json`);
import hre, { ethers, upgrades } from 'hardhat';

// Check this doc to understand how the OZ upgrade plugin works: https://docs.openzeppelin.com/upgrades-plugins/1.x/

async function main() {
  const [deployer] = await ethers.getSigners();

  if (process.env.NETWORK == 'mainnet') {
    await hre.network.provider.send('hardhat_setBalance', [deployer.address, '0x100000000000000000000000000']);
  }

  console.log('\n🦋 Deploying Morpho contracts for Compound');
  console.log('👩 Deployer account:', deployer.address);
  console.log('🤑 Account balance:', formatEther(await deployer.getBalance()));

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

  const morphoProxyAdmin = await upgrades.erc1967.getAdminAddress(morpho.address);
  const morphoImplementationAddress = await upgrades.erc1967.getImplementationAddress(morpho.address);

  console.log('🎉 Morpho Proxy deployed to address:', morpho.address);
  console.log('🎉 Morpho Proxy Admin deployed to address:', morphoProxyAdmin);
  console.log('🎉 Morpho Implementation deployed to address:', morphoImplementationAddress);

  console.log('\n🦋 Verifying Morpho Proxy on Tenderly...');
  await hre.tenderly.verify({
    name: 'Morpho Proxy',
    address: morpho.address,
  });
  console.log('🎉 Morpho Proxy verified!');

  console.log('\n🦋 Verifying Morpho Proxy Admin on Tenderly...');
  await hre.tenderly.verify({
    name: 'Morpho Proxy Admin',
    address: morphoProxyAdmin,
  });
  console.log('🎉 Morpho Proxy Admin verified!');

  console.log('\n🦋 Verifying Morpho Implementation on Tenderly...');
  await hre.tenderly.verify({
    name: 'Morpho Implementation',
    address: morphoImplementationAddress,
  });
  console.log('🎉 Morpho Implementation verified!');

  /// POSITIONS MANAGER DEPLOYMENT ///

  console.log('\n🦋 Deploying Lens...');
  const Lens = await ethers.getContractFactory('Lens');
  const lens = await Lens.deploy(morpho.address);
  await lens.deployed();
  console.log('🎉 Lens deployed to address:', lens.address);

  console.log('\n🦋 Verifying Lens on Tenderly...');
  await hre.tenderly.verify({
    name: 'Lens',
    address: lens.address,
  });
  console.log('🎉 Lens verified!');

  /// MARKETS CREATION ///

  console.log('\n🦋 Creating markets...');
  await morpho.connect(deployer).createMarket(config.tokens.cEth.address);
  await morpho.connect(deployer).createMarket(config.tokens.cDai.address);
  await morpho.connect(deployer).createMarket(config.tokens.cUsdc.address);
  console.log('🎉 Markets created!\n');

  /// REWARDS MANAGER DEPLOYMENT ///

  console.log('\n🦋 Deploying RewardsManager...');
  const RewardsManager = await ethers.getContractFactory('RewardsManager');
  const rewardsManager = await RewardsManager.deploy(morpho.address);
  await rewardsManager.deployed();
  console.log('🎉 RewardsManager deployed to address:', rewardsManager.address);

  console.log('\n🦋 Verifying RewardsManager on Tenderly...');
  await hre.tenderly.verify({
    name: 'RewardsManager',
    address: rewardsManager.address,
  });
  console.log('🎉 RewardsManager verified!');

  await morpho.connect(deployer).setRewardsManager(rewardsManager.address);
  console.log('🎉 RewardsManager set on Morpho!');

  /// MORPHO TOKEN DEPLOYMENT ///

  console.log('\n🦋 Deploying MorphoToken...');
  const MorphoToken = await ethers.getContractFactory('MorphoToken');
  const morphoToken = await MorphoToken.deploy(deployer.address);
  await morphoToken.deployed();
  console.log('🎉 MorphoToken deployed to address:', morphoToken.address);

  console.log('\n🦋 Verifying MorphoToken on Tenderly...');
  await hre.tenderly.verify({
    name: 'MorphoToken',
    address: morphoToken.address,
  });
  console.log('🎉 MorphoToken verified!');

  /// ORACLE DEPLOYMENT ///

  console.log('\n🦋 Deploying Oracle...');
  const Oracle = await ethers.getContractFactory('DumbOracle');
  const oracle = await Oracle.deploy();
  await oracle.deployed();
  console.log('🎉 Oracle deployed to address:', oracle.address);

  console.log('\n🦋 Verifying Oracle on Tenderly...');
  await hre.tenderly.verify({
    name: 'Oracle',
    address: oracle.address,
  });
  console.log('🎉 Oracle verified!');

  /// INCENTIVES VAULT DEPLOYMENT ///

  console.log('\n🦋 Deploying IncentivesVault...');
  const IncentivesVault = await ethers.getContractFactory('IncentivesVault');
  const incentivesVault = await IncentivesVault.deploy(
    morpho.address,
    config.compound.comptroller.address,
    morphoToken.address,
    deployer.address,
    oracle.address
  );
  await incentivesVault.deployed();
  console.log('🎉 IncentivesVault deployed to address:', incentivesVault.address);

  console.log('\n🦋 Verifying IncentivesVault on Tenderly...');
  await hre.tenderly.verify({
    name: 'IncentivesVault',
    address: incentivesVault.address,
  });
  console.log('🎉 IncentivesVault verified!');

  await morpho.setIncentivesVault(incentivesVault.address);
  console.log('🎉 IncentivesVault set on Morpho!');

  await morpho.toggleCompRewardsActivation();
  console.log('🎉 COMP rewards activated on Morpho!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
