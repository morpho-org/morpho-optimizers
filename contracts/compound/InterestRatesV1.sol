// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IInterestRates.sol";

import "./libraries/CompoundMath.sol";
import "./libraries/Types.sol";

/// @title Interest Rates computation V1.
/// @notice Smart contract computing the exchange rates on Morpho.
contract InterestRatesV1 is IInterestRates {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct RateParams {
        uint256 p2pExchangeRate; // The P2P exchange rate.
        uint256 poolExchangeRate; // The pool exchange rate.
        uint256 lastPoolExchangeRate; // The pool exchange rate at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pAmount; // Sum of all stored P2P balance in supply or borrow (in P2P unit).
        uint256 p2pDelta; // Sum of all stored P2P in supply or borrow (in P2P unit).
    }

    struct GrowthFactors {
        uint256 p2pGrowthFactor; // P2P growth factor (between now and the last update).
        uint256 poolGrowthFactor; // Pool growth factor (between now and the last update).
    }

    /// STORAGE ///

    uint256 public constant WAD = 1e18;
    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).

    /// EXTERNAL ///

    /// @dev Computes and return new P2P exchange rates.
    /// @param _params Computation parameters.
    /// @return newSupplyP2PExchangeRate The updated supplyP2PExchangeRate.
    /// @return newBorrowP2PExchangeRate The updated borrowP2PExchangeRate.
    function computeP2PExchangeRates(Types.Params memory _params)
        external
        pure
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        (
            GrowthFactors memory supplyGrowthFactors,
            GrowthFactors memory borrowGrowthFactors
        ) = _computeGrowthFactors(
            _params.poolSupplyExchangeRate,
            _params.poolBorrowExchangeRate,
            _params.lastPoolSupplyExchangeRate,
            _params.lastPoolBorrowExchangeRate,
            _params.reserveFactor
        );

        RateParams memory supplyParams = RateParams({
            p2pExchangeRate: _params.supplyP2PExchangeRate,
            poolExchangeRate: _params.poolSupplyExchangeRate,
            lastPoolExchangeRate: _params.lastPoolSupplyExchangeRate,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.supplyP2PAmount,
            p2pDelta: _params.delta.supplyP2PDelta
        });
        RateParams memory borrowParams = RateParams({
            p2pExchangeRate: _params.borrowP2PExchangeRate,
            poolExchangeRate: _params.poolBorrowExchangeRate,
            lastPoolExchangeRate: _params.lastPoolBorrowExchangeRate,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.borrowP2PAmount,
            p2pDelta: _params.delta.borrowP2PDelta
        });

        newSupplyP2PExchangeRate = _computeNewP2PRate(supplyParams, supplyGrowthFactors);
        newBorrowP2PExchangeRate = _computeNewP2PRate(borrowParams, borrowGrowthFactors);
    }

    /// @dev Computes and return the new supply P2P exchange rate.
    /// @param _params Computation parameters.
    /// @return The updated supplyP2PExchangeRate.
    function computeSupplyP2PExchangeRate(Types.Params memory _params)
        external
        pure
        returns (uint256)
    {
        RateParams memory supplyParams = RateParams({
            p2pExchangeRate: _params.supplyP2PExchangeRate,
            poolExchangeRate: _params.poolSupplyExchangeRate,
            lastPoolExchangeRate: _params.lastPoolSupplyExchangeRate,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.supplyP2PAmount,
            p2pDelta: _params.delta.supplyP2PDelta
        });

        (GrowthFactors memory supplyGrowthFactors, ) = _computeGrowthFactors(
            _params.poolSupplyExchangeRate,
            _params.poolBorrowExchangeRate,
            _params.lastPoolSupplyExchangeRate,
            _params.lastPoolBorrowExchangeRate,
            _params.reserveFactor
        );

        return _computeNewP2PRate(supplyParams, supplyGrowthFactors);
    }

    /// @dev Computes and return the new borrow P2P exchange rate.
    /// @param _params Computation parameters.
    /// @return The updated borrowP2PExchangeRate.
    function computeBorrowP2PExchangeRate(Types.Params memory _params)
        external
        pure
        returns (uint256)
    {
        RateParams memory borrowParams = RateParams({
            p2pExchangeRate: _params.borrowP2PExchangeRate,
            poolExchangeRate: _params.poolBorrowExchangeRate,
            lastPoolExchangeRate: _params.lastPoolBorrowExchangeRate,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.borrowP2PAmount,
            p2pDelta: _params.delta.borrowP2PDelta
        });

        (, GrowthFactors memory borrowGrowthFactors) = _computeGrowthFactors(
            _params.poolSupplyExchangeRate,
            _params.poolBorrowExchangeRate,
            _params.lastPoolSupplyExchangeRate,
            _params.lastPoolBorrowExchangeRate,
            _params.reserveFactor
        );

        return _computeNewP2PRate(borrowParams, borrowGrowthFactors);
    }

    /// INTERNAL ///

    /// @dev Computes and returns supply P2P growthfactor and borrow P2P growthfactor.
    /// @param _poolSupplyExchangeRate The current pool supply exchange rate.
    /// @param _poolBorrowExchangeRate The current pool borrow exchange rate.
    /// @param _lastPoolSupplyExchangeRate The pool supply exchange rate at last update.
    /// @param _lastPoolBorrowExchangeRate The pool borrow exchange rate at last update.
    /// @param _reserveFactor The reserve factor percentage (10 000 = 100%).
    /// @return supplyGrowthFactors_ The supply growth factors paramaters.
    /// @return borrowGrowthFactors_ The borrow growth factors paramaters.
    function _computeGrowthFactors(
        uint256 _poolSupplyExchangeRate,
        uint256 _poolBorrowExchangeRate,
        uint256 _lastPoolSupplyExchangeRate,
        uint256 _lastPoolBorrowExchangeRate,
        uint256 _reserveFactor
    )
        internal
        pure
        returns (
            GrowthFactors memory supplyGrowthFactors_,
            GrowthFactors memory borrowGrowthFactors_
        )
    {
        supplyGrowthFactors_.poolGrowthFactor = _poolSupplyExchangeRate.div(
            _lastPoolSupplyExchangeRate
        );
        borrowGrowthFactors_.poolGrowthFactor = _poolBorrowExchangeRate.div(
            _lastPoolBorrowExchangeRate
        );
        supplyGrowthFactors_.p2pGrowthFactor =
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 *
                    supplyGrowthFactors_.poolGrowthFactor +
                    borrowGrowthFactors_.poolGrowthFactor)) /
            3 /
            MAX_BASIS_POINTS +
            (_reserveFactor * supplyGrowthFactors_.poolGrowthFactor) /
            MAX_BASIS_POINTS;

        borrowGrowthFactors_.p2pGrowthFactor =
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 *
                    supplyGrowthFactors_.poolGrowthFactor +
                    borrowGrowthFactors_.poolGrowthFactor)) /
            3 /
            MAX_BASIS_POINTS +
            (_reserveFactor * borrowGrowthFactors_.poolGrowthFactor) /
            MAX_BASIS_POINTS;
    }

    /// @dev Computes and returns the new P2P exchange rate.
    /// @param _params Computation parameters.
    /// @param _growthFactors The growth factors.
    /// @return newP2PExchangeRate The updated P2P exchange rate.
    function _computeNewP2PRate(RateParams memory _params, GrowthFactors memory _growthFactors)
        internal
        pure
        returns (uint256 newP2PExchangeRate)
    {
        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PExchangeRate = _params.p2pExchangeRate.mul(_growthFactors.p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                _params.p2pDelta.mul(_params.poolExchangeRate).div(_params.p2pExchangeRate).div(
                    _params.p2pAmount
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PExchangeRate = _params.p2pExchangeRate.mul(
                (WAD - shareOfTheDelta).mul(_growthFactors.p2pGrowthFactor) +
                    shareOfTheDelta.mul(_growthFactors.poolGrowthFactor)
            );
        }
    }
}
