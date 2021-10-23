const { utils, BigNumber } = require('ethers');
const Decimal = require('decimal.js');

const SCALE = utils.parseUnits('1');
const RAY = BigNumber.from(10).pow(27);

const underlyingToScaledBalance = (underlyingAmount, normalizedIncome) => {
  return underlyingAmount.mul(RAY).div(normalizedIncome);
};

const scaledBalanceToUnderlying = (scaledBalance, normalizedIncome) => {
  return scaledBalance.mul(normalizedIncome).div(RAY);
};

const underlyingToMUnit = (underlyingAmount, mUnitExchangeRate) => {
  return underlyingAmount.mul(RAY).div(mUnitExchangeRate);
};

const mUnitToUnderlying = (mUnitAmount, mUnitExchangeRate) => {
  return mUnitAmount.mul(mUnitExchangeRate).div(RAY);
};

const underlyingToAdUnit = (underlyingAmount, normalizedVariableDebt) => {
  return underlyingAmount.mul(RAY).div(normalizedVariableDebt);
};

const aDUnitToUnderlying = (aDUnitAmount, normalizedVariableDebt) => {
  return aDUnitAmount.mul(normalizedVariableDebt).div(RAY);
};

const computeNewMorphoExchangeRate = (currentExchangeRate, p2pBPY, currentBlockNumber, lastUpdateBlockNumber) => {
  // Use of decimal.js library for better accuracy
  const bpy = new Decimal(p2pBPY.toString());
  const ray = new Decimal('1e27');
  const exponent = new Decimal(currentBlockNumber - lastUpdateBlockNumber);
  const val = bpy.div(ray).add(1);
  const multiplier = val.pow(exponent);
  const newExchangeRate = new Decimal(currentExchangeRate.toString()).mul(multiplier);
  return Decimal.round(newExchangeRate);
};

// TODO: re-write it
const computeNewBorrowIndex = (borrowRate, blockDelta, borrowIndex) => {
  return borrowRate.mul(blockDelta).mul(borrowIndex).div(SCALE).add(borrowIndex);
};

module.exports = {
  RAY,
  SCALE,
  underlyingToScaledBalance,
  scaledBalanceToUnderlying,
  underlyingToMUnit,
  mUnitToUnderlying,
  underlyingToAdUnit,
  aDUnitToUnderlying,
  computeNewMorphoExchangeRate,
  computeNewBorrowIndex,
};
