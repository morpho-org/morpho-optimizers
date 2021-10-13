const { BigNumber } = require('ethers');
const config = require('@config/ethereum-config.json').ropsten;

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
  const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
  await redBlackBinaryTree.deployed();

  console.log('RedBlackBinaryTree address:', redBlackBinaryTree.address);

  const CompLikeMarketsManager = await ethers.getContractFactory('CompLikeMarketsManager');
  const compLikeMarketsManager = await CompLikeMarketsManager.deploy();
  await compLikeMarketsManager.deployed();

  console.log('CompLikeMarketsManager address:', compLikeMarketsManager.address);

  const CompPositionsManager = await ethers.getContractFactory('CompPositionsManager', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const compPositionsManager = await CompPositionsManager.deploy(compLikeMarketsManager.address, config.compound.comptroller.address);
  await compPositionsManager.deployed();

  console.log('CompPositionsManager address:', compPositionsManager.address);

  await compLikeMarketsManager.connect(deployer).setCompPositionsManager(compPositionsManager.address);
  await compLikeMarketsManager.connect(deployer).createMarkets([config.tokens.cDai.address, config.tokens.cUsdc.address, config.tokens.cBat.address, config.tokens.cZrx.address]);
  await compLikeMarketsManager.connect(deployer).updateThreshold(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
  await compLikeMarketsManager.connect(deployer).listMarket(config.tokens.cDai.address);
  await compLikeMarketsManager.connect(deployer).listMarket(config.tokens.cUsdc.address);
  await compLikeMarketsManager.connect(deployer).listMarket(config.tokens.cBat.address);
  await compLikeMarketsManager.connect(deployer).listMarket(config.tokens.cZrx.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
