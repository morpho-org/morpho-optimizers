// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IInterestRates.sol";

import "./libraries/CompoundMath.sol";
import "./libraries/Types.sol";

/// @title Interest Rates computation V1.
/// @notice Smart contract computing the indexes on Morpho.
contract InterestRatesV1 is IInterestRates {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct RateParams {
        uint256 p2pIndex; // The P2P index.
        uint256 poolIndex; // The pool index.
        uint256 lastPoolIndex; // The pool index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pAmount; // Sum of all stored P2P balance in supply or borrow (in P2P unit).
        uint256 p2pDelta; // Sum of all stored P2P in supply or borrow (in P2P unit).
    }

    /// STORAGE ///

    uint256 public constant WAD = 1e18;
    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).

    /// EXTERNAL ///

    /// @notice Computes and return new P2P indexes.
    /// @param _params Computation parameters.
    /// @return newP2PSupplyIndex The updated p2pSupplyIndex.
    /// @return newP2PBorrowIndex The updated p2pBorrowIndex.
    function computeP2PIndexes(Types.Params memory _params)
        external
        pure
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        (
            uint256 supplyP2PGrowthFactor,
            uint256 supplyPoolGrowthaFactor,
            uint256 borrowP2PGrowthFactor,
            uint256 borrowPoolGrowthFactor
        ) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pCursor
        );

        RateParams memory supplyParams = RateParams({
            p2pIndex: _params.p2pSupplyIndex,
            poolIndex: _params.poolSupplyIndex,
            lastPoolIndex: _params.lastPoolSupplyIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.supplyP2PAmount,
            p2pDelta: _params.delta.supplyP2PDelta
        });
        RateParams memory borrowParams = RateParams({
            p2pIndex: _params.p2pBorrowIndex,
            poolIndex: _params.poolBorrowIndex,
            lastPoolIndex: _params.lastPoolBorrowIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.borrowP2PAmount,
            p2pDelta: _params.delta.borrowP2PDelta
        });

        newP2PSupplyIndex = _computeNewP2PRate(
            supplyParams,
            supplyP2PGrowthFactor,
            supplyPoolGrowthaFactor
        );
        newP2PBorrowIndex = _computeNewP2PRate(
            borrowParams,
            borrowP2PGrowthFactor,
            borrowPoolGrowthFactor
        );
    }

    /// @notice Computes and return the new peer-to-peer supply index.
    /// @param _params Computation parameters.
    /// @return The updated p2pSupplyIndex.
    function computeP2PSupplyIndex(Types.Params memory _params) external pure returns (uint256) {
        RateParams memory supplyParams = RateParams({
            p2pIndex: _params.p2pSupplyIndex,
            poolIndex: _params.poolSupplyIndex,
            lastPoolIndex: _params.lastPoolSupplyIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.supplyP2PAmount,
            p2pDelta: _params.delta.supplyP2PDelta
        });

        (
            uint256 supplyP2PGrowthFactor,
            uint256 supplyPoolGrowthaFactor,
            ,

        ) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pCursor
        );

        return _computeNewP2PRate(supplyParams, supplyP2PGrowthFactor, supplyPoolGrowthaFactor);
    }

    /// @notice Computes and return the new peer-to-peer borrow index.
    /// @param _params Computation parameters.
    /// @return The updated p2pBorrowIndex.
    function computeP2PBorrowIndex(Types.Params memory _params) external pure returns (uint256) {
        RateParams memory borrowParams = RateParams({
            p2pIndex: _params.p2pBorrowIndex,
            poolIndex: _params.poolBorrowIndex,
            lastPoolIndex: _params.lastPoolBorrowIndex,
            reserveFactor: _params.reserveFactor,
            p2pAmount: _params.delta.borrowP2PAmount,
            p2pDelta: _params.delta.borrowP2PDelta
        });

        (, , uint256 borrowP2PGrowthFactor, uint256 borrowPoolGrowthFactor) = _computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.reserveFactor,
            _params.p2pCursor
        );

        return _computeNewP2PRate(borrowParams, borrowP2PGrowthFactor, borrowPoolGrowthFactor);
    }

    /// INTERNAL ///

    /// @dev Computes and returns supply P2P growthfactor and borrow P2P growthfactor.
    /// @param _poolSupplyIndex The current pool supply index.
    /// @param _poolBorrowIndex The current pool borrow index.
    /// @param _lastPoolSupplyIndex The pool supply index at last update.
    /// @param _lastPoolBorrowIndex The pool borrow index at last update.
    /// @param _reserveFactor The reserve factor percentage (10 000 = 100%).
    /// @return supplyP2PGrowthFactor_ The supply P2P growth factor.
    /// @return supplyPoolGrowthFactor_ The supply pool growth factor.
    /// @return borrowP2PGrowthFactor_ The borrow P2P growth factor.
    /// @return borrowPoolGrowthFactor_ The borrow pool growth factor.
    function _computeGrowthFactors(
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex,
        uint256 _lastPoolSupplyIndex,
        uint256 _lastPoolBorrowIndex,
        uint256 _reserveFactor,
        uint256 _p2pCursor
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
        supplyPoolGrowthFactor_ = _poolSupplyIndex.div(_lastPoolSupplyIndex);
        borrowPoolGrowthFactor_ = _poolBorrowIndex.div(_lastPoolBorrowIndex);
        uint256 p2pGrowthFactor = ((MAX_BASIS_POINTS - _p2pCursor) *
            supplyPoolGrowthFactor_ +
            _p2pCursor *
            borrowPoolGrowthFactor_) / MAX_BASIS_POINTS;
        supplyP2PGrowthFactor_ =
            p2pGrowthFactor -
            (_reserveFactor * (p2pGrowthFactor - supplyPoolGrowthFactor_)) /
            MAX_BASIS_POINTS;
        borrowP2PGrowthFactor_ =
            p2pGrowthFactor +
            (_reserveFactor * (borrowPoolGrowthFactor_ - p2pGrowthFactor)) /
            MAX_BASIS_POINTS;
    }

    /// @dev Computes and returns the new P2P index.
    /// @param _params Computation parameters.
    /// @param _p2pGrowthFactor The P2P growth factor.
    /// @param _poolGrowthFactor The pool growth factor.
    /// @return newP2PIndex The updated P2P index.
    function _computeNewP2PRate(
        RateParams memory _params,
        uint256 _p2pGrowthFactor,
        uint256 _poolGrowthFactor
    ) internal pure returns (uint256 newP2PIndex) {
        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PIndex = _params.p2pIndex.mul(_p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                _params.p2pDelta.mul(_params.poolIndex).div(_params.p2pIndex).div(
                    _params.p2pAmount
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PIndex = _params.p2pIndex.mul(
                (WAD - shareOfTheDelta).mul(_p2pGrowthFactor) +
                    shareOfTheDelta.mul(_poolGrowthFactor)
            );
        }
    }
}
