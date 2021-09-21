const { utils, BigNumber } = require('ethers');
const Decimal = require('decimal.js');

const SCALE = utils.parseUnits('1');

const underlyingToCToken = (underlyingAmount, exchangeRateCurrent) => {
  return underlyingAmount.mul(SCALE).div(exchangeRateCurrent);
};

const cTokenToUnderlying = (cTokenAmount, exchangeRateCurrent) => {
  return cTokenAmount.mul(exchangeRateCurrent).div(SCALE);
};

const underlyingToMUnit = (underlyingAmount, exchangeRateCurrent) => {
  return underlyingAmount.mul(SCALE).div(exchangeRateCurrent);
};

const mUnitToUnderlying = (mUnitAmount, exchangeRateCurrent) => {
  return mUnitAmount.mul(exchangeRateCurrent).div(SCALE);
};

const bigNumberMin = (a, b) => {
  if (a.lte(b)) return a;
  return b;
};

// Removes the last digits of a number: used to remove dust errors
const removeDigitsBigNumber = (decimalsToRemove, number) => number.sub(number.mod(BigNumber.from(10).pow(decimalsToRemove))).div(BigNumber.from(10).pow(decimalsToRemove));
const removeDigits = (decimalsToRemove, number) => (number - (number % 10 ** decimalsToRemove)) / 10 ** decimalsToRemove;

const computeNewMorphoExchangeRate = (currentExchangeRate, BPY, currentBlockNumber, lastUpdateBlockNumber) => {
  // Use of decimal.js library for better accuracy
  const bpy = new Decimal(BPY.toString());
  const scale = new Decimal('1e18');
  const exponent = new Decimal(currentBlockNumber - lastUpdateBlockNumber);
  const val = bpy.div(scale).add(1);
  const multiplier = val.pow(exponent);
  const newExchangeRate = new Decimal(currentExchangeRate.toString()).mul(multiplier);
  return Decimal.round(newExchangeRate);
};

const computeNewBorrowIndex = (borrowRate, blockDelta, borrowIndex) => {
  return borrowRate.mul(blockDelta).mul(borrowIndex).div(SCALE).add(borrowIndex);
};

const to6Decimals = (value) => value.div(BigNumber.from(10).pow(12));

module.exports = {
  SCALE,
  underlyingToCToken,
  cTokenToUnderlying,
  underlyingToMUnit,
  mUnitToUnderlying,
  removeDigitsBigNumber,
  bigNumberMin,
  removeDigits,
  computeNewMorphoExchangeRate,
  computeNewBorrowIndex,
  to6Decimals,
};
