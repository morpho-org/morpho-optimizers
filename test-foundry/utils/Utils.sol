// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";

contract Utils is DSTest {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant SECOND_PER_YEAR = 31536000;
    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

    uint256 internal constant PERCENT_BASE = 10000;
    uint256 internal constant AVERAGE_BLOCK_TIME = 2;

    function to6Decimals(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

    function underlyingToScaledBalance(uint256 _scaledBalance, uint256 _normalizedIncome)
        internal
        pure
        returns (uint256)
    {
        return (_scaledBalance * RAY) / _normalizedIncome;
    }

    function scaledBalanceToUnderlying(uint256 _scaledBalance, uint256 _normalizedIncome)
        internal
        pure
        returns (uint256)
    {
        return (_scaledBalance * _normalizedIncome) / RAY;
    }

    function underlyingToAdUnit(uint256 _underlyingAmount, uint256 _normalizedVariableDebt)
        internal
        pure
        returns (uint256)
    {
        return (_underlyingAmount * RAY) / _normalizedVariableDebt;
    }

    function aDUnitToUnderlying(uint256 _aDUnitAmount, uint256 _normalizedVariableDebt)
        internal
        pure
        returns (uint256)
    {
        return (_aDUnitAmount * _normalizedVariableDebt) / RAY;
    }

    function underlyingToP2PUnit(uint256 _underlyingAmount, uint256 _p2pExchangeRate)
        internal
        pure
        returns (uint256)
    {
        return (_underlyingAmount * RAY) / _p2pExchangeRate;
    }

    function p2pUnitToUnderlying(uint256 _p2pUnitAmount, uint256 _p2pExchangeRate)
        internal
        pure
        returns (uint256)
    {
        return (_p2pUnitAmount * _p2pExchangeRate) / RAY;
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
}
