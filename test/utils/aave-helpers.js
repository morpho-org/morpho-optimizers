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

const computeNewMorphoExchangeRate = (currentExchangeRate, p2pBPY, currentTimestamp, lastUpdateTimestamp) => {
  // Use of decimal.js library for better accuracy
  const bpy = new Decimal(p2pBPY.toString());
  const ray = new Decimal('1e27');
  const exponent = new Decimal(currentTimestamp - lastUpdateTimestamp);
  const val = bpy.div(ray).add(1);
  const multiplier = val.pow(exponent);
  const bigNumberMultiplier = BigNumber.from(multiplier.mul(ray).toFixed().toString());
  const newExchangeRate = currentExchangeRate.mul(bigNumberMultiplier).div(RAY);
  return newExchangeRate;
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
