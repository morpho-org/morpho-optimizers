const { BigNumber } = require('ethers');

async function main() {
  // Kovan
  const CDAI_ADDRESS = "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643";
  const CUSDC_ADDRESS = "0x39aa39c021dfbae8fac545936693ac917d5e7563";
  const CBAT_ADDRESS = "0x6c8c6b02e7b2be14d4fa6022dfd6d75921d90e4e";
  const CZRX_ADDRESS = "0xb3319f5d18bc0d84dd1b4825dcde5d5f7266d407";
  const PROXY_COMPTROLLER_ADDRESS = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";

	const [deployer] = await ethers.getSigners();

	console.log("Deploying contracts with the account:", deployer.address);

	console.log("Account balance:", (await deployer.getBalance()).toString());

	const CompoundModule = await ethers.getContractFactory("CompoundModule");
	const compoudModule = await CompoundModule.deploy(PROXY_COMPTROLLER_ADDRESS);
  await compoundModule.deployed();

  await compoundModule.connect(deployer).createMarkets([CDAI_ADDRESS, CUSDC_ADDRESS, CBAT_ADDRESS, CZRX_ADDRESS]);
  await compoundModule.connect(deployer).updateThreshold(CUSDC_ADDRESS, 0, BigNumber.from(1).pow(6));
  await compoundModule.connect(deployer).listMarket(CDAI_ADDRESS);
  await compoundModule.connect(deployer).listMarket(CUSDC_ADDRESS);
  await compoundModule.connect(deployer).listMarket(CBAT_ADDRESS);
  await compoundModule.connect(deployer).listMarket(CZRX_ADDRESS);

	console.log("CompoundModule address:", compoudModule.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });