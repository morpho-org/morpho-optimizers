import { utils, BigNumber } from 'ethers';
import Decimal from 'decimal.js';

const WAD: BigNumber = utils.parseUnits('1');

const underlyingToCToken = (underlyingAmount: BigNumber, exchangeRateCurrent: BigNumber): BigNumber => {
  return underlyingAmount.mul(WAD).div(exchangeRateCurrent);
};

const cTokenToUnderlying = (cTokenAmount: BigNumber, exchangeRateCurrent: BigNumber): BigNumber => {
  return cTokenAmount.mul(exchangeRateCurrent).div(WAD);
};

const underlyingToP2pUnit = (underlyingAmount: BigNumber, p2pUnitExchangeRate: BigNumber): BigNumber => {
  return underlyingAmount.mul(WAD).div(p2pUnitExchangeRate);
};

const p2pUnitToUnderlying = (p2pUnitAmount: BigNumber, p2pUnitExchangeRate: BigNumber | string): BigNumber => {
  return p2pUnitAmount.mul(p2pUnitExchangeRate).div(WAD);
};

const underlyingToCdUnit = (underlyingAmount: BigNumber, borrowIndex: BigNumber): BigNumber => {
  return underlyingAmount.mul(WAD).div(borrowIndex);
};

const cDUnitToUnderlying = (cDUnitAmount: BigNumber, borrowIndex: BigNumber): BigNumber => {
  return cDUnitAmount.mul(borrowIndex).div(WAD);
};

const computeNewMorphoExchangeRate = (
  currentExchangeRate: BigNumber,
  p2pBPY: BigNumber,
  currentBlockNumber: number,
  lastUpdateBlockNumber: number
): Decimal => {
  // Use of decimal.js library for better accuracy
  const bpy = new Decimal(p2pBPY.toString());
  const scale = new Decimal('1e18');
  const exponent = new Decimal(currentBlockNumber - lastUpdateBlockNumber);
  const val = bpy.div(scale).add(1);
  const multiplier = val.pow(exponent);
  const newExchangeRate = new Decimal(currentExchangeRate.toString()).mul(multiplier);
  return Decimal.round(newExchangeRate);
};

const computeNewBorrowIndex = (borrowRate: BigNumber, blockDelta: BigNumber, borrowIndex: BigNumber): BigNumber => {
  return borrowRate.mul(blockDelta).mul(borrowIndex).div(WAD).add(borrowIndex);
};

export {
  WAD,
  underlyingToCToken,
  cTokenToUnderlying,
  underlyingToP2pUnit,
  p2pUnitToUnderlying,
  underlyingToCdUnit,
  cDUnitToUnderlying,
  computeNewMorphoExchangeRate,
  computeNewBorrowIndex,
};
