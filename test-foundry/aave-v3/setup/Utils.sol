// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

import "forge-std/Test.sol";

contract Utils is Test {
    using WadRayMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 5_000;

    uint256 internal constant PERCENT_BASE = 10_000;
    uint256 internal constant AVERAGE_BLOCK_TIME = 2;

    function to6Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

    function to8Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e10;
    }

    function underlyingToScaledBalance(uint256 _scaledBalance, uint256 _normalizedIncome)
        internal
        pure
        returns (uint256)
    {
        return _scaledBalance.rayDiv(_normalizedIncome);
    }

    function scaledBalanceToUnderlying(uint256 _scaledBalance, uint256 _normalizedIncome)
        internal
        pure
        returns (uint256)
    {
        return _scaledBalance.rayMul(_normalizedIncome);
    }

    function underlyingToAdUnit(uint256 _underlyingAmount, uint256 _normalizedVariableDebt)
        internal
        pure
        returns (uint256)
    {
        return _underlyingAmount.rayDiv(_normalizedVariableDebt);
    }

    function aDUnitToUnderlying(uint256 _aDUnitAmount, uint256 _normalizedVariableDebt)
        internal
        pure
        returns (uint256)
    {
        return _aDUnitAmount.rayMul(_normalizedVariableDebt);
    }

    function underlyingToP2PUnit(uint256 _underlyingAmount, uint256 _p2pExchangeRate)
        internal
        pure
        returns (uint256)
    {
        return _underlyingAmount.rayDiv(_p2pExchangeRate);
    }

    function p2pUnitToUnderlying(uint256 _p2pUnitAmount, uint256 _p2pExchangeRate)
        internal
        pure
        returns (uint256)
    {
        return _p2pUnitAmount.rayMul(_p2pExchangeRate);
    }

    function getAbsDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a > b) {
            return a - b;
        }

        return b - a;
    }

    function testEquality(uint256 _firstValue, uint256 _secondValue) internal {
        assertApproxEqAbs(_firstValue, _secondValue, 20);
    }

    function testEquality(
        uint256 _firstValue,
        uint256 _secondValue,
        string memory err
    ) internal {
        assertApproxEqAbs(_firstValue, _secondValue, 20, err);
    }

    function testEqualityLarge(uint256 _firstValue, uint256 _secondValue) internal {
        assertApproxEqAbs(_firstValue, _secondValue, 1e15);
    }

    function testEqualityLarge(
        uint256 _firstValue,
        uint256 _secondValue,
        string memory err
    ) internal {
        assertApproxEqAbs(_firstValue, _secondValue, 1e16, err);
    }

    /// @dev calculates compounded interest over a period of time.
    ///   To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
    ///   (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
    /// @param _rate The APR to use in the computation.
    /// @param _elapsedTime The amount of time during to get the interest for.
    /// @return results in ray
    function computeCompoundedInterest(uint256 _rate, uint256 _elapsedTime)
        public
        pure
        returns (uint256)
    {
        uint256 rate = _rate / SECONDS_PER_YEAR;

        if (_elapsedTime == 0) return WadRayMath.RAY;

        if (_elapsedTime == 1) return WadRayMath.RAY + rate;

        uint256 ratePowerTwo = rate.rayMul(rate);
        uint256 ratePowerThree = ratePowerTwo.rayMul(rate);

        return
            WadRayMath.RAY +
            rate *
            _elapsedTime +
            (_elapsedTime * (_elapsedTime - 1) * ratePowerTwo) /
            2 +
            (_elapsedTime * (_elapsedTime - 1) * (_elapsedTime - 2) * ratePowerThree) /
            6;
    }

    function bytes32ToAddress(bytes32 _bytes) internal pure returns (address) {
        return address(uint160(uint256(_bytes)));
    }
}
