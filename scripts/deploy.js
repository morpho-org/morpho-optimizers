const { BigNumber } = require('ethers');
const config = require(`@config/${process.env.NETWORK}-config.json`);

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
  const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
  await redBlackBinaryTree.deployed();

  console.log('RedBlackBinaryTree address:', redBlackBinaryTree.address);

  const UpdatePositions = await ethers.getContractFactory('UpdatePositions', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const updatePositions = await UpdatePositions.deploy();
  await updatePositions.deployed();

  const MorphoMarketsManagerForCompound = await ethers.getContractFactory('MorphoMarketsManagerForCompound');
  const morphoMarketsManagerForCompound = await MorphoMarketsManagerForCompound.deploy();
  await morphoMarketsManagerForCompound.deployed();

  console.log('MorphoMarketsManagerForCompound address:', morphoMarketsManagerForCompound.address);

  const MorphoPositionsManagerForCompound = await ethers.getContractFactory('MorphoPositionsManagerForCompound', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const morphoPositionsManagerForCompound = await MorphoPositionsManagerForCompound.deploy(morphoMarketsManagerForCompound.address, config.compound.comptroller.address, updatePositions.address);
  await morphoPositionsManagerForCompound.deployed();

  console.log('MorphoPositionsManagerForCompound address:', morphoPositionsManagerForCompound.address);

  await morphoMarketsManagerForCompound.connect(deployer).setPositionsManagerForCompound(morphoPositionsManagerForCompound.address);
  await morphoMarketsManagerForCompound.connect(deployer).createMarket(config.tokens.cDai.address);
  await morphoMarketsManagerForCompound.connect(deployer).createMarket(config.tokens.cUsdc.address);
  await morphoMarketsManagerForCompound.connect(deployer).updateThreshold(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
