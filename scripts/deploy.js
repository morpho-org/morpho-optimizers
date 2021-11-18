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

  const MarketsManagerForCompound = await ethers.getContractFactory('MarketsManagerForCompound');
  const marketsManagerForCompound = await MarketsManagerForCompound.deploy();
  await marketsManagerForCompound.deployed();

  console.log('MarketsManagerForCompound address:', marketsManagerForCompound.address);

  const PositionsManagerForCompound = await ethers.getContractFactory('PositionsManagerForCompound', {
    libraries: {
      RedBlackBinaryTree: redBlackBinaryTree.address,
    },
  });
  const positionsManagerForCompound = await PositionsManagerForCompound.deploy(marketsManagerForCompound.address, config.compound.comptroller.address, updatePositions.address);
  await positionsManagerForCompound.deployed();

  console.log('PositionsManagerForCompound address:', positionsManagerForCompound.address);

  await marketsManagerForCompound.connect(deployer).setPositionsManagerForCompound(positionsManagerForCompound.address);
  await marketsManagerForCompound.connect(deployer).createMarket(config.tokens.cDai.address, BigNumber.from(1).pow(6));
  await marketsManagerForCompound.connect(deployer).createMarket(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
