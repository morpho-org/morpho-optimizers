import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';

const WAD: BigNumber = utils.parseUnits('1');
const MAX_INT: BigNumber = BigNumber.from('2').pow(BigNumber.from('256')).sub(BigNumber.from('1'));

const bigNumberMin = (a: BigNumber, b: BigNumber): BigNumber => {
  if (a.lte(b)) return a;
  return b;
};

// Removes the last digits of a number: used to remove dust errors
const removeDigitsBigNumber = (decimalsToRemove: number, number: BigNumber): BigNumber =>
  number.sub(number.mod(BigNumber.from(10).pow(decimalsToRemove))).div(BigNumber.from(10).pow(decimalsToRemove));

const roundBigNumber = (decimalsToRemove: number, number: BigNumber): BigNumber => {
  let precision: BigNumber = BigNumber.from(10).pow(decimalsToRemove);
  let division: BigNumber = number.div(precision);
  let floor: BigNumber = precision.mul(division);
  let ceiling: BigNumber = precision.mul(division.add(1));
  return number.sub(floor).gt(precision.div(2)) ? ceiling : floor;
};

const removeDigits = (decimalsToRemove: number, number: number): number =>
  (number - (number % 10 ** decimalsToRemove)) / 10 ** decimalsToRemove;

const to6Decimals = (value: BigNumber): BigNumber => value.div(BigNumber.from(10).pow(12));

const getTokens = async (
  signerAddress: string,
  signerType: string,
  signers: Signer[],
  tokenConfig: any,
  amount: BigNumber
): Promise<Contract> => {
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [signerAddress],
  });
  const signerAccount = await ethers.getSigner(signerAddress);
  await hre.network.provider.send('hardhat_setBalance', [signerAddress, utils.hexValue(utils.parseUnits('1000'))]);

  // Transfer token
  const token = await ethers.getContractAt(require(tokenConfig.abi), tokenConfig.address, signerAccount);
  await Promise.all(
    signers.map(async (signer) => {
      if (signerType == 'whale') {
        await token.connect(signerAccount).transfer(signer.getAddress(), amount);
      } else {
        await token.mint(signer.getAddress(), amount, { from: signerAddress });
      }
    })
  );

  return token;
};

export { WAD, MAX_INT, removeDigitsBigNumber, bigNumberMin, removeDigits, to6Decimals, getTokens, roundBigNumber };
