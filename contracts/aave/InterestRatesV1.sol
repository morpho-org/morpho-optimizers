// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IInterestRates.sol";
import "./positions-manager-parts/PositionsManagerForAaveStorage.sol";

import "./libraries/Math.sol";
import "./libraries/Types.sol";

contract InterestRatesV1 is IInterestRates {
    using Math for uint256;

    /// STRUCT ///

    struct Vars {
        uint256 shareOfTheDelta; // Share of delta in the total P2P amount.
        uint256 supplyP2PGrowthFactor; // Supply growth factor (between now and the last update).
        uint256 borrowP2PGrowthFactor; // Borrow growth factor (between now and the last update).
    }

    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).

    /// EXTERNAL ///

    /// @notice Computes and return new P2P exchange rates.
    /// @param _params Parameters:
    ///             supplyP2pExchangeRate The current supply P2P exchange rate.
    ///             borrowP2pExchangeRate The current borrow P2P exchange rate.
    ///             poolSupplyExchangeRate The current pool supply exchange rate.
    ///             poolBorrowExchangeRate The current pool borrow exchange rate.
    ///             lastPoolSupplyExchangeRate The pool supply exchange rate at last update.
    ///             lastPoolBorrowExchangeRate The pool borrow exchange rate at last update.
    ///             reserveFactor The reserve factor percentage (10 000 = 100%).
    ///             delta The deltas and P2P amounts.
    /// @return newSupplyP2PExchangeRate The updated supplyP2PExchangeRate.
    /// @return newBorrowP2PExchangeRate The updated borrowP2PExchangeRate.
    function computeP2PExchangeRates(Types.Params memory _params)
        public
        pure
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        Vars memory vars;
        (vars.supplyP2PGrowthFactor, vars.borrowP2PGrowthFactor) = _computeGrowthFactors(
            _params.poolSupplyExchangeRate,
            _params.poolBorrowExchangeRate,
            _params.lastPoolSupplyExchangeRate,
            _params.lastPoolBorrowExchangeRate,
            _params.reserveFactor
        );

        if (_params.delta.supplyP2PAmount == 0 || _params.delta.supplyP2PDelta == 0) {
            newSupplyP2PExchangeRate = _params.supplyP2pExchangeRate.rayMul(
                vars.supplyP2PGrowthFactor
            );
        } else {
            vars.shareOfTheDelta = Math.min(
                _params
                .delta
                .supplyP2PDelta
                .wadToRay()
                .rayMul(_params.poolSupplyExchangeRate)
                .rayDiv(_params.supplyP2pExchangeRate)
                .rayDiv(_params.delta.supplyP2PAmount.wadToRay()),
                Math.ray() // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newSupplyP2PExchangeRate = _params.supplyP2pExchangeRate.rayMul(
                (Math.ray() - vars.shareOfTheDelta).rayMul(vars.supplyP2PGrowthFactor) +
                    vars.shareOfTheDelta.rayMul(_params.poolSupplyExchangeRate).rayDiv(
                        _params.lastPoolSupplyExchangeRate
                    )
            );
        }
        if (_params.delta.borrowP2PAmount == 0 || _params.delta.borrowP2PDelta == 0) {
            newBorrowP2PExchangeRate = _params.borrowP2pExchangeRate.rayMul(
                vars.borrowP2PGrowthFactor
            );
        } else {
            vars.shareOfTheDelta = Math.min(
                _params
                .delta
                .borrowP2PDelta
                .wadToRay()
                .rayMul(_params.poolBorrowExchangeRate)
                .rayDiv(_params.borrowP2pExchangeRate)
                .rayDiv(_params.delta.borrowP2PAmount.wadToRay()),
                Math.ray() // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newBorrowP2PExchangeRate = _params.borrowP2pExchangeRate.rayMul(
                (Math.ray() - vars.shareOfTheDelta).rayMul(vars.borrowP2PGrowthFactor) +
                    vars.shareOfTheDelta.rayMul(_params.poolBorrowExchangeRate).rayDiv(
                        _params.lastPoolBorrowExchangeRate
                    )
            );
        }
    }

    /// @notice Computes and returns supply P2P growthfactor and borrow P2P growthfactor.
    /// @param _poolSupplyExchangeRate The current pool supply exchange rate.
    /// @param _poolBorrowExchangeRate The current pool borrow exchange rate.
    /// @param _lastPoolSupplyExchangeRate The pool supply exchange rate at last update.
    /// @param _lastPoolBorrowExchangeRate The pool borrow exchange rate at last update.
    /// @param _reserveFactor The reserve factor percentage (10 000 = 100%).
    /// @return supplyP2PGrowthFactor The supply P2P growthfactor.
    /// @return borrowP2PGrowthFactor The borrow P2P growthfactor.
    function _computeGrowthFactors(
        uint256 _poolSupplyExchangeRate,
        uint256 _poolBorrowExchangeRate,
        uint256 _lastPoolSupplyExchangeRate,
        uint256 _lastPoolBorrowExchangeRate,
        uint256 _reserveFactor
    ) internal pure returns (uint256 supplyP2PGrowthFactor, uint256 borrowP2PGrowthFactor) {
        supplyP2PGrowthFactor =
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 *
                    _poolSupplyExchangeRate.rayDiv(_lastPoolSupplyExchangeRate) +
                    _poolBorrowExchangeRate.rayDiv(_lastPoolBorrowExchangeRate))) /
            MAX_BASIS_POINTS /
            3 -
            (_reserveFactor * _poolSupplyExchangeRate.rayDiv(_lastPoolSupplyExchangeRate)) /
            MAX_BASIS_POINTS;
        borrowP2PGrowthFactor =
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 *
                    _poolSupplyExchangeRate.rayDiv(_lastPoolSupplyExchangeRate) +
                    _poolBorrowExchangeRate.rayDiv(_lastPoolBorrowExchangeRate))) /
            MAX_BASIS_POINTS /
            3 +
            (_reserveFactor * _poolBorrowExchangeRate.rayDiv(_lastPoolBorrowExchangeRate)) /
            MAX_BASIS_POINTS;
    }

    /// @notice Computes and returns approximate P2P rates for a specific market.
    /// @param _poolSupplyRate The market's supply rate on the pool (in ray).
    /// @param _poolBorrowRate The market's borrow rate on the pool (in ray).
    /// @param _reserveFactor The markets's reserve factor (in basis points).
    /// @return p2pSupplyRate_ The market's supply rate in P2P (in ray).
    /// @return p2pBorrowRate_ The market's borrow rate in P2P (in ray).
    function computeApproxRates(
        uint256 _poolSupplyRate,
        uint256 _poolBorrowRate,
        uint256 _reserveFactor
    ) external pure override returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_) {
        // rate = 2/3 * poolSupplyRate + 1/3 * poolBorrowRate.
        uint256 rate = (2 * _poolSupplyRate + _poolBorrowRate) / 3;

        p2pSupplyRate_ = rate - (_reserveFactor * (rate - _poolSupplyRate)) / MAX_BASIS_POINTS;
        p2pBorrowRate_ = rate + (_reserveFactor * (_poolBorrowRate - rate)) / MAX_BASIS_POINTS;
    }
}
