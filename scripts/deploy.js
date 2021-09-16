const { BigNumber } = require('ethers');

async function main() {
  // Kovan
  // const CDAI_ADDRESS = "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643";
  // const CUSDC_ADDRESS = "0x39aa39c021dfbae8fac545936693ac917d5e7563";
  // const CBAT_ADDRESS = "0x6c8c6b02e7b2be14d4fa6022dfd6d75921d90e4e";
  // const CZRX_ADDRESS = "0xb3319f5d18bc0d84dd1b4825dcde5d5f7266d407";
  // const PROXY_COMPTROLLER_ADDRESS = "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b";

  // Rinkeby
  // const CDAI_ADDRESS = '0x6d7f0754ffeb405d23c51ce938289d4835be3b14';
  // const CUSDC_ADDRESS = '0x5b281a6dda0b271e91ae35de655ad301c976edb1';
  // const CBAT_ADDRESS = '0xebf1a11532b93a529b5bc942b4baa98647913002';
  // const CZRX_ADDRESS = '0x52201ff1720134bbbbb2f6bc97bf3715490ec19b';
  // const PROXY_COMPTROLLER_ADDRESS = '0x2eaa9d77ae4d8f9cdd9faacd44016e746485bddb';

  // Ropsten
  const CDAI_ADDRESS = '0xbc689667c13fb2a04f09272753760e38a95b998c';
  const CUSDC_ADDRESS = '0x2973e69b20563bcc66dc63bde153072c33ef37fe';
  const CBAT_ADDRESS = '0xaf50a5a6af87418dac1f28f9797ceb3bfb62750a';
  const CZRX_ADDRESS = '0x6b8b0d7875b4182fb126877023fb93b934dd302a';
  const PROXY_COMPTROLLER_ADDRESS = '0xcfa7b0e37f5ac60f3ae25226f5e39ec59ad26152';

  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with the account:', deployer.address);

  console.log('Account balance:', (await deployer.getBalance()).toString());

  const Morpho = await ethers.getContractFactory('Morpho');
  const morpho = await Morpho.deploy(PROXY_COMPTROLLER_ADDRESS);
  await morpho.deployed();

  console.log('Morpho address:', morpho.address);

  const CompoundModule = await ethers.getContractFactory('CompoundModule');
  const compoundModule = await CompoundModule.deploy(morpho.address, PROXY_COMPTROLLER_ADDRESS);
  await compoundModule.deployed();

  console.log('CompoundModule address:', compoundModule.address);

  await morpho.connect(deployer).setCompoundModule(compoundModule.address);
  await morpho.connect(deployer).createMarkets([CDAI_ADDRESS, CUSDC_ADDRESS, CBAT_ADDRESS, CZRX_ADDRESS]);
  await morpho.connect(deployer).updateThreshold(CUSDC_ADDRESS, 0, BigNumber.from(1).pow(6));
  await morpho.connect(deployer).listMarket(CDAI_ADDRESS);
  await morpho.connect(deployer).listMarket(CUSDC_ADDRESS);
  await morpho.connect(deployer).listMarket(CBAT_ADDRESS);
  await morpho.connect(deployer).listMarket(CZRX_ADDRESS);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
