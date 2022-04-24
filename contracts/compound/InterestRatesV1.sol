// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IInterestRates.sol";

import "./libraries/CompoundMath.sol";
import "./libraries/Types.sol";

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

    /// STORAGE ///

    uint256 public constant WAD = 1e18;
    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).

    /// EXTERNAL ///

    /// @notice Computes and return new P2P exchange rates.
    /// @param _params Computation parameters.
    /// @return newSupplyP2PExchangeRate The updated supplyP2PExchangeRate.
    /// @return newBorrowP2PExchangeRate The updated borrowP2PExchangeRate.
    function computeP2PExchangeRates(Types.Params memory _params)
        external
        pure
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        (
            uint256 supplyP2PGrowthFactor,
            uint256 supplyPoolGrowthaFactor,
            uint256 borrowP2PGrowthFactor,
            uint256 borrowPoolGrowthFactor
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

        newSupplyP2PExchangeRate = _computeNewP2PRate(
            supplyParams,
            supplyP2PGrowthFactor,
            supplyPoolGrowthaFactor
        );
        newBorrowP2PExchangeRate = _computeNewP2PRate(
            borrowParams,
            borrowP2PGrowthFactor,
            borrowPoolGrowthFactor
        );
    }

    /// @notice Computes and return the new supply P2P exchange rate.
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

        (
            uint256 supplyP2PGrowthFactor,
            uint256 supplyPoolGrowthaFactor,
            ,

        ) = _computeGrowthFactors(
            _params.poolSupplyExchangeRate,
            _params.poolBorrowExchangeRate,
            _params.lastPoolSupplyExchangeRate,
            _params.lastPoolBorrowExchangeRate,
            _params.reserveFactor
        );

        return _computeNewP2PRate(supplyParams, supplyP2PGrowthFactor, supplyPoolGrowthaFactor);
    }

    /// @notice Computes and return the new borrow P2P exchange rate.
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

        (, , uint256 borrowP2PGrowthFactor, uint256 borrowPoolGrowthFactor) = _computeGrowthFactors(
            _params.poolSupplyExchangeRate,
            _params.poolBorrowExchangeRate,
            _params.lastPoolSupplyExchangeRate,
            _params.lastPoolBorrowExchangeRate,
            _params.reserveFactor
        );

        return _computeNewP2PRate(borrowParams, borrowP2PGrowthFactor, borrowPoolGrowthFactor);
    }

    /// INTERNAL ///

    /// @dev Computes and returns supply P2P growthfactor and borrow P2P growthfactor.
    /// @param _poolSupplyExchangeRate The current pool supply exchange rate.
    /// @param _poolBorrowExchangeRate The current pool borrow exchange rate.
    /// @param _lastPoolSupplyExchangeRate The pool supply exchange rate at last update.
    /// @param _lastPoolBorrowExchangeRate The pool borrow exchange rate at last update.
    /// @param _reserveFactor The reserve factor percentage (10 000 = 100%).
    /// @return supplyP2PGrowthFactor_ The supply P2P growth factor.
    /// @return supplyPoolGrowthFactor_ The supply pool growth factor.
    /// @return borrowP2PGrowthFactor_ The borrow P2P growth factor.
    /// @return borrowPoolGrowthFactor_ The borrow pool growth factor.
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
            uint256 supplyP2PGrowthFactor_,
            uint256 supplyPoolGrowthFactor_,
            uint256 borrowP2PGrowthFactor_,
            uint256 borrowPoolGrowthFactor_
        )
    {
        supplyPoolGrowthFactor_ = _poolSupplyExchangeRate.div(_lastPoolSupplyExchangeRate);
        borrowPoolGrowthFactor_ = _poolBorrowExchangeRate.div(_lastPoolBorrowExchangeRate);
        supplyP2PGrowthFactor_ =
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 * supplyPoolGrowthFactor_ + borrowPoolGrowthFactor_)) /
            3 /
            MAX_BASIS_POINTS +
            (_reserveFactor * supplyPoolGrowthFactor_) /
            MAX_BASIS_POINTS;

        borrowP2PGrowthFactor_ =
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 * supplyPoolGrowthFactor_ + borrowPoolGrowthFactor_)) /
            3 /
            MAX_BASIS_POINTS +
            (_reserveFactor * borrowPoolGrowthFactor_) /
            MAX_BASIS_POINTS;
    }

    /// @dev Computes and returns the new P2P exchange rate.
    /// @param _params Computation parameters.
    /// @param _p2pGrowthFactor The P2P growth factor.
    /// @param _poolGrowthFactor The pool growth factor.
    /// @return newP2PExchangeRate The updated P2P exchange rate.
    function _computeNewP2PRate(
        RateParams memory _params,
        uint256 _p2pGrowthFactor,
        uint256 _poolGrowthFactor
    ) internal pure returns (uint256 newP2PExchangeRate) {
        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PExchangeRate = _params.p2pExchangeRate.mul(_p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                _params.p2pDelta.mul(_params.poolExchangeRate).div(_params.p2pExchangeRate).div(
                    _params.p2pAmount
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PExchangeRate = _params.p2pExchangeRate.mul(
                (WAD - shareOfTheDelta).mul(_p2pGrowthFactor) +
                    shareOfTheDelta.mul(_poolGrowthFactor)
            );
        }
    }
}
