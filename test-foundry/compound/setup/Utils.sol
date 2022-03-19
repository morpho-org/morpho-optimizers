// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/compound/libraries/CompoundMath.sol";

import "ds-test/test.sol";

contract Utils is DSTest {
    using CompoundMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;
    uint256 internal constant PERCENT_BASE = 10000;

    function to6Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

    function to8Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e10;
    }

    function underlyingToPoolSupplyBalance(uint256 _poolSupplyBalance, uint256 _exchangeRateCurrent)
        internal
        pure
        returns (uint256)
    {
        return _poolSupplyBalance.div(_exchangeRateCurrent);
    }

    function poolSupplyBalanceToUnderlying(uint256 _poolSupplyBalance, uint256 _exchangeRateCurrent)
        internal
        pure
        returns (uint256)
    {
        return _poolSupplyBalance.mul(_exchangeRateCurrent);
    }

    function underlyingToDebtUnit(uint256 _underlyingAmount, uint256 _borrowIndex)
        internal
        pure
        returns (uint256)
    {
        return _underlyingAmount.div(_borrowIndex);
    }

    function debtUnitToUnderlying(uint256 _debtUnitAmount, uint256 _borrowIndex)
        internal
        pure
        returns (uint256)
    {
        return _debtUnitAmount.mul(_borrowIndex);
    }

    function underlyingToP2PUnit(uint256 _underlyingAmount, uint256 _p2pExchangeRate)
        internal
        pure
        returns (uint256)
    {
        return _underlyingAmount.div(_p2pExchangeRate);
    }

    function p2pUnitToUnderlying(uint256 _p2pUnitAmount, uint256 _p2pExchangeRate)
        internal
        pure
        returns (uint256)
    {
        return _p2pUnitAmount.mul(_p2pExchangeRate);
    }

    function getAbsDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > b) {
            return a - b;
        }

        return b - a;
    }

    function testEquality(uint256 _firstValue, uint256 _secondValue) internal {
        assertApproxEq(_firstValue, _secondValue, 20);
    }

    function testEquality(
        uint256 _firstValue,
        uint256 _secondValue,
        string memory err
    ) internal {
        assertApproxEq(_firstValue, _secondValue, 20, err);
    }

    /// @dev Computes the compounded interest over a number of blocks.
    ///   To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
    ///   (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
    /// @param _rate The BPY to use in the computation.
    /// @param _elapsedBlocks The number of blocks passed since te last computation.
    /// @return The result in wad.
    function _computeCompoundedInterest(uint256 _rate, uint256 _elapsedBlocks)
        internal
        pure
        returns (uint256)
    {
        if (_elapsedBlocks == 0) return WAD;
        if (_elapsedBlocks == 1) return WAD + _rate;

        uint256 ratePowerTwo = _rate.mul(_rate);
        uint256 ratePowerThree = ratePowerTwo.mul(_rate);

        return
            WAD +
            _rate *
            _elapsedBlocks +
            (_elapsedBlocks * (_elapsedBlocks - 1) * ratePowerTwo) /
            2 +
            (_elapsedBlocks * (_elapsedBlocks - 1) * (_elapsedBlocks - 2) * ratePowerThree) /
            6;
    }
}
