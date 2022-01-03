import { utils, BigNumber } from 'ethers';
import Decimal from 'decimal.js';

const WAD: BigNumber = utils.parseUnits('1');
const RAY: BigNumber = BigNumber.from(10).pow(27);
const PERCENT_BASE: BigNumber = BigNumber.from(10000);

const underlyingToScaledBalance = (underlyingAmount: BigNumber, normalizedIncome: BigNumber): BigNumber => {
  return underlyingAmount.mul(RAY).div(normalizedIncome);
};

const scaledBalanceToUnderlying = (scaledBalance: BigNumber, normalizedIncome: BigNumber): BigNumber => {
  return scaledBalance.mul(normalizedIncome).div(RAY);
};

const underlyingToP2PUnit = (underlyingAmount: BigNumber, p2pExchangeRate: BigNumber): BigNumber => {
  return underlyingAmount.mul(RAY).div(p2pExchangeRate);
};

const p2pUnitToUnderlying = (p2pUnitAmount: BigNumber, p2pExchangeRate: BigNumber): BigNumber => {
  return p2pUnitAmount.mul(p2pExchangeRate).div(RAY);
};

const underlyingToAdUnit = (underlyingAmount: BigNumber, normalizedVariableDebt: BigNumber): BigNumber => {
  return underlyingAmount.mul(RAY).div(normalizedVariableDebt);
};

const aDUnitToUnderlying = (aDUnitAmount: BigNumber, normalizedVariableDebt: BigNumber): BigNumber => {
  return aDUnitAmount.mul(normalizedVariableDebt).div(RAY);
};

const computeNewMorphoExchangeRate = (
  currentExchangeRate: BigNumber,
  p2pSPY: BigNumber,
  currentTimestamp: number,
  lastUpdateTimestamp: number
): BigNumber => {
  // Use of decimal.js library for better accuracy
  const spy = new Decimal(p2pSPY.toString());
  const ray = new Decimal('1e27');
  const exponent = new Decimal(currentTimestamp - lastUpdateTimestamp);
  const val = spy.div(ray).add(1);
  const multiplier = val.pow(exponent);
  const bigNumberMultiplier = BigNumber.from(multiplier.mul(ray).toFixed().toString());
  const newExchangeRate = currentExchangeRate.mul(bigNumberMultiplier).div(RAY);
  return newExchangeRate;
};

const computeNewBorrowIndex = (borrowRate: BigNumber, blockDelta: BigNumber, borrowIndex: BigNumber): BigNumber => {
  return borrowRate.mul(blockDelta).mul(borrowIndex).div(WAD).add(borrowIndex);
};

export {
  RAY,
  WAD,
  PERCENT_BASE,
  underlyingToScaledBalance,
  scaledBalanceToUnderlying,
  underlyingToP2PUnit,
  p2pUnitToUnderlying,
  underlyingToAdUnit,
  aDUnitToUnderlying,
  computeNewMorphoExchangeRate,
  computeNewBorrowIndex,
};
