const { BigNumber } = require('ethers');
const config = require('@config/ethereum-config.json').ropsten;

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const Morpho = await ethers.getContractFactory('Morpho');
  const morpho = await Morpho.deploy(config.compound.comptroller.address);
  await morpho.deployed();

  console.log('Morpho address:', morpho.address);

  const CompoundModule = await ethers.getContractFactory('CompoundModule');
  const compoundModule = await CompoundModule.deploy(morpho.address, config.compound.comptroller.address);
  await compoundModule.deployed();

  console.log('CompoundModule address:', compoundModule.address);

  await morpho.connect(deployer).setCompoundModule(compoundModule.address);
  await morpho.connect(deployer).createMarkets([config.tokens.cDai.address, config.tokens.cUsdc.address, config.tokens.cBat.address, config.tokens.cZrx.address]);
  await morpho.connect(deployer).updateThreshold(config.tokens.cUsdc.address, 0, BigNumber.from(1).pow(6));
  await morpho.connect(deployer).listMarket(config.tokens.cDai.address);
  await morpho.connect(deployer).listMarket(config.tokens.cUsdc.address);
  await morpho.connect(deployer).listMarket(config.tokens.cBat.address);
  await morpho.connect(deployer).listMarket(config.tokens.cZrx.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
