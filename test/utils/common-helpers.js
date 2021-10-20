const { utils, BigNumber } = require('ethers');
const hre = require('hardhat');

const SCALE = utils.parseUnits('1');

const bigNumberMin = (a, b) => {
  if (a.lte(b)) return a;
  return b;
};

// Removes the last digits of a number: used to remove dust errors
const removeDigitsBigNumber = (decimalsToRemove, number) => number.sub(number.mod(BigNumber.from(10).pow(decimalsToRemove))).div(BigNumber.from(10).pow(decimalsToRemove));
const removeDigits = (decimalsToRemove, number) => (number - (number % 10 ** decimalsToRemove)) / 10 ** decimalsToRemove;
const to6Decimals = (value) => value.div(BigNumber.from(10).pow(12));

const getTokens = async (signerAddress, signerType, signers, tokenConfig, amount) => {
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

module.exports = {
  SCALE,
  removeDigitsBigNumber,
  bigNumberMin,
  removeDigits,
  to6Decimals,
  getTokens,
};
