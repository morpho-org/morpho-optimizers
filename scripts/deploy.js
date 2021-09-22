const { BigNumber } = require('ethers');
const config = require('@config/ethereum-config.json').ropsten;

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);
  console.log('Account balance:', (await deployer.getBalance()).toString());

  const CompMarketsManager = await ethers.getContractFactory('CompMarketsManager');
  const compMarketsManager = await CompMarketsManager.deploy(config.compound.comptroller.address);
  await compMarketsManager.deployed();

  console.log('CompMarketsManager address:', compMarketsManager.address);

  const CompPositionsManager = await ethers.getContractFactory('CompPositionsManager');
  const compPositionsManager = await CompPositionsManager.deploy(compMarketsManager.address, config.compound.comptroller.address);
  await compPositionsManager.deployed();

  console.log('CompPositionsManager address:', compPositionsManager.address);

  await compMarketsManager.connect(deployer).setCompPositionsManager(compPositionsManager.address);
  await compMarketsManager.connect(deployer).createMarkets([config.tokens.cDai.address, config.tokens.cUsdc.address, config.tokens.cBat.address, config.tokens.cZrx.address]);
  await compMarketsManager.connect(deployer).updateThreshold(config.tokens.cUsdc.address, 0, BigNumber.from(1).pow(6));
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
