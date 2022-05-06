/* eslint-disable no-console */
const config = require(`@config/${process.env.NETWORK}-config.json`);
import hre, { ethers, upgrades } from 'hardhat';

// Check this doc to understand how the OZ upgrade plugin works: https://docs.openzeppelin.com/upgrades-plugins/1.x/

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('\n🦋 Upgrading Morpho contracts for Compound');
  console.log('👩 Deployer account:', deployer.address);
  console.log('🤑 Account balance:', (await deployer.getBalance()).toString());

  const positionsManagerAddress = '0xaa3d9c6b6379a1d3611b41c73552f61d68694f76';
  const interestRatesAddress = '0xa519a5421a004fbb6473169f9d24d5aa13e30697';
  const morphoProxyAddress = '0x9c8f4e4d0298e0711fc15d3674bd40ae0c5977a0';

  /// MORPHO UPGRADE ///

  const maxGas = { supply: 3e6, borrow: 3e6, withdraw: 3e6, repay: 3e6 };

  console.log('\n🦋 Upgrading Morpho...');

  // Part to update
  const Morpho = await ethers.getContractFactory('Morpho');
  await upgrades.upgradeProxy(morphoProxyAddress, Morpho, {
    call: {
      fn: 'initialize',
      args: [
        positionsManagerAddress,
        interestRatesAddress,
        config.compound.comptroller.address,
        1,
        maxGas,
        100,
        config.tokens.cEth.address,
        config.tokens.wEth.address,
      ],
    },
    unsafeAllow: ['delegatecall'],
  });
  const morphoImplementationAddress = await upgrades.erc1967.getImplementationAddress(morphoProxyAddress);

  console.log('🎉 Morpho Proxy deployed to address:', morphoProxyAddress);
  console.log('🎉 Morpho Implementation deployed to address:', morphoImplementationAddress);

  console.log('\n🦋 Verifying Morpho Implementation on Tenderly...');
  await hre.tenderly.verify({
    name: 'Morpho Implementation',
    address: morphoImplementationAddress,
  });
  console.log('🎉 Morpho Implementation verified!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
