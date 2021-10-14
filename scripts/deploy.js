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

  const MorphoMarketsManagerForCompLike = await ethers.getContractFactory('MorphoMarketsManagerForCompLike');
  const compMarketsManager = await MorphoMarketsManagerForCompLike.deploy();
  await compMarketsManager.deployed();

  console.log('MorphoMarketsManagerForCompLike address:', compMarketsManager.address);

  const PositionsManagerForCompLike = await ethers.getContractFactory('PositionsManagerForCompLike', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const positionsManagerForCompLike = await PositionsManagerForCompLike.deploy(compMarketsManager.address, config.compound.comptroller.address);
  await positionsManagerForCompLike.deployed();

  console.log('PositionsManagerForCompLike address:', positionsManagerForCompLike.address);

  await compMarketsManager.connect(deployer).setPositionsManagerForCompLike(positionsManagerForCompLike.address);
  await compMarketsManager.connect(deployer).createMarkets([config.tokens.cDai.address, config.tokens.cUsdc.address, config.tokens.cBat.address, config.tokens.cZrx.address]);
  await compMarketsManager.connect(deployer).updateThreshold(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
  await compMarketsManager.connect(deployer).listMarket(config.tokens.cDai.address);
  await compMarketsManager.connect(deployer).listMarket(config.tokens.cUsdc.address);
  await compMarketsManager.connect(deployer).listMarket(config.tokens.cBat.address);
  await compMarketsManager.connect(deployer).listMarket(config.tokens.cZrx.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
