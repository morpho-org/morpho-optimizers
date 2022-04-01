// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/IInterestRates.sol";

import "./libraries/Math.sol";

contract InterestRatesV1 is IInterestRates {
    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).

    /// EXTERNAL ///

    /// @notice Computes and returns P2P rates for a specific market.
    /// @param _poolSupplyRate The market's supply rate on the pool (in ray).
    /// @param _poolBorrowRate The market's borrow rate on the pool (in ray).
    /// @param _reserveFactor The markets's reserve factor (in basis points).
    /// @return p2pSupplyRate The market's supply rate in P2P (in ray).
    /// @return p2pBorrowRate The market's borrow rate in P2P (in ray).
    function computeRates(
        uint256 _poolSupplyRate,
        uint256 _poolBorrowRate,
        uint256 _reserveFactor
    ) external pure override returns (uint256 p2pSupplyRate, uint256 p2pBorrowRate) {
        // rate = 2/3 * poolSupplyRate + 1/3 * poolBorrowRate, as there are more suppliers than borrowers.
        uint256 rate = (2 * _poolSupplyRate + _poolBorrowRate) / 3;

        p2pSupplyRate = rate - (_reserveFactor * (rate - _poolSupplyRate)) / MAX_BASIS_POINTS;
        p2pBorrowRate = rate + (_reserveFactor * (_poolBorrowRate - rate)) / MAX_BASIS_POINTS;
    }
}
