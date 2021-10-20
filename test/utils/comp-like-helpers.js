const { utils } = require('ethers');
const Decimal = require('decimal.js');

const SCALE = utils.parseUnits('1');

const underlyingToCToken = (underlyingAmount, exchangeRateCurrent) => {
  return underlyingAmount.mul(SCALE).div(exchangeRateCurrent);
};

const cTokenToUnderlying = (cTokenAmount, exchangeRateCurrent) => {
  return cTokenAmount.mul(exchangeRateCurrent).div(SCALE);
};

const underlyingToMUnit = (underlyingAmount, mUnitExchangeRate) => {
  return underlyingAmount.mul(SCALE).div(mUnitExchangeRate);
};

const mUnitToUnderlying = (mUnitAmount, mUnitExchangeRate) => {
  return mUnitAmount.mul(mUnitExchangeRate).div(SCALE);
};

const underlyingToCdUnit = (underlyingAmount, borrowIndex) => {
  return underlyingAmount.mul(SCALE).div(borrowIndex);
};

const cDUnitToUnderlying = (cDUnitAmount, borrowIndex) => {
  return cDUnitAmount.mul(borrowIndex).div(SCALE);
};

const computeNewMorphoExchangeRate = (currentExchangeRate, p2pBPY, currentBlockNumber, lastUpdateBlockNumber) => {
  // Use of decimal.js library for better accuracy
  const bpy = new Decimal(p2pBPY.toString());
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

module.exports = {
  SCALE,
  underlyingToCToken,
  cTokenToUnderlying,
  underlyingToMUnit,
  mUnitToUnderlying,
  underlyingToCdUnit,
  cDUnitToUnderlying,
  computeNewMorphoExchangeRate,
  computeNewBorrowIndex,
};
