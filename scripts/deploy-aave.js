const { BigNumber } = require('ethers');
const config = require('@config/polygon/config.json').mumbai;

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
  const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
  await redBlackBinaryTree.deployed();

  console.log('RedBlackBinaryTree address:', redBlackBinaryTree.address);

  const MorphoMarketsManagerForAave = await ethers.getContractFactory('MorphoMarketsManagerForAave');
  const marketsManagerForAave = await MorphoMarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
  await marketsManagerForAave.deployed();

  console.log('MorphoMarketsManagerForAave address:', marketsManagerForAave.address);

  const PositionsManagerForAave = await ethers.getContractFactory('MorphoPositionsManagerForAave', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const positionsManagerForAave = await PositionsManagerForAave.deploy(marketsManagerForAave.address, config.aave.lendingPoolAddressesProvider.address);
  await positionsManagerForAave.deployed();

  console.log('MorphoPositionsManagerForAave address:', positionsManagerForAave.address);

  await marketsManagerForAave.connect(deployer).setPositionsManager(positionsManagerForAave.address);
  await marketsManagerForAave.connect(deployer).createMarket(config.tokens.aDai.address);
  await marketsManagerForAave.connect(deployer).createMarket(config.tokens.aUsdc.address);
  await marketsManagerForAave.connect(deployer).updateThreshold(config.tokens.aUsdc.address, BigNumber.from(1).pow(6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
