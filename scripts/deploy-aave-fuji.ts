/* eslint-disable no-console */
import { BigNumber } from 'ethers';
import hre, { ethers } from 'hardhat';
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  const deployerAddress = await deployer.getAddress();
  console.log('\n🦋 Deploying Morpho contracts for Aave');
  console.log('👩 Deployer account:', deployerAddress);
  console.log('🤑 Account balance:', (await deployer.getBalance()).toString());

  console.log('\n🦋 Deploying SwapManagerUniV2...');
  const SwapManager = await ethers.getContractFactory('SwapManagerUniV2');
  const swapManager = await SwapManager.deploy(config.joeRouter.address, config.tokens.morpho.address, config.tokens.wavax.address);
  await swapManager.deployed();
  console.log('🎉 SwapManagerUniV2 deployed to address:', swapManager.address);

  console.log('\n🦋 Deploying MarketsManagerForAave...');
  const MarketsManager = await ethers.getContractFactory('MarketsManagerForAave');
  const marketsManager = await MarketsManager.deploy(config.aave.lendingPool.address);
  await marketsManager.deployed();
  console.log('🎉 MarketsManagerForAave deployed to address:', marketsManager.address);

  //console.log('\n🦋 Verifying MarketsManagerForAave on Tenderly...');
  //await hre.tenderly.verify({
  //  name: 'MarketsManagerForAave',
  //  address: marketsManagerForAave.address,
  //});
  //console.log('🎉 MarketsManagerForAave verified!');

  console.log('\n🦋 Deploying PositionsManagerForAave...');
  const PositionsManager = await ethers.getContractFactory('PositionsManagerForAave');
  const positionsManager = await PositionsManager.deploy(
    marketsManager.address,
    config.aave.lendingPoolAddressesProvider.address,
    swapManager.address,
    {
      supply: 3e6,
      borrow: 3e6,
      withdraw: 1.5e6,
      repay: 1.5e6,
    }
  );
  await positionsManager.deployed();
  console.log('🎉 PositionsManagerForAave deployed to address:', positionsManager.address);

  //console.log('\n🦋 Verifying PositionsManagerForAave on Tenderly...');
  //await hre.tenderly.verify({
  //  name: 'PositionsManagerForAave',
  //  address: positionsManagerForAave.address,
  //});
  //console.log('🎉 PositionsManagerForAave verified!');

  console.log('\n🦋 Deploying RewardsManagerForAaveOnAvalanche...');
  const RewardsManager = await ethers.getContractFactory('RewardsManagerForAaveOnAvalanche');
  const rewardsManager = await RewardsManager.deploy(config.aave.lendingPool.address, positionsManager.address);
  await rewardsManager.deployed();
  console.log('🎉 RewardsManagerForAaveOnAvalanche deployed to address:', rewardsManager.address);

  console.log('\n🦋 Configure MarketsManagerForAave...');
  await marketsManager.setPositionsManager(positionsManager.address);

  console.log('\n🦋 Configure PositionsManagerForAave...');
  await positionsManager.setAaveIncentivesController(config.aave.aaveIncentivesController.address);
  await positionsManager.setTreasuryVault(deployerAddress);
  await positionsManager.setRewardsManager(rewardsManager.address);

  console.log('\n🦋 Configure RewardsManagerForAave...');
  await rewardsManager.setAaveIncentivesController(config.aave.aaveIncentivesController.address);

  console.log('\n🦋 Creating markets...');
  await marketsManager.createMarket(config.tokens.wavax.address, BigNumber.from(10).pow(18));
  await marketsManager.createMarket(config.tokens.weth.address, BigNumber.from(10).pow(18));
  await marketsManager.createMarket(config.tokens.wbtc.address, BigNumber.from(100));
  await marketsManager.createMarket(config.tokens.usdt.address, BigNumber.from(10).pow(6));

  console.log('🎉 Finished!\n');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
