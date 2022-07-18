// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../libraries/aave/PercentageMath.sol";
import "../libraries/aave/WadRayMath.sol";
import "../libraries/Math.sol";
import "./Types.sol";

library InterestRatesModel {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis points).

    /// STRUCTS ///

    struct GrowthFactors {
        uint256 poolSupplyGrowthFactor; // The pool's supply index growth factor (in ray).
        uint256 poolBorrowGrowthFactor; // The pool's borrow index growth factor (in ray).
        uint256 p2pSupplyGrowthFactor; // Peer-to-peer supply index growth factor (in ray).
        uint256 p2pBorrowGrowthFactor; // Peer-to-peer borrow index growth factor (in ray).
    }

    struct P2PIndexComputeParams {
        uint256 poolGrowthFactor; // The pool's index growth factor (in wad).
        uint256 p2pGrowthFactor; // Morpho peer-to-peer's median index growth factor (in wad).
        uint256 lastPoolIndex; // The pool's last stored index.
        uint256 lastP2PIndex; // Morpho's last stored peer-to-peer index.
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
    }

    struct P2PRateComputeParams {
        uint256 poolRate; // The pool's index growth factor (in wad).
        uint256 p2pRate; // Morpho peer-to-peer's median index growth factor (in wad).
        uint256 poolIndex; // The pool's last stored index.
        uint256 p2pIndex; // Morpho's last stored peer-to-peer index.
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
        uint256 reserveFactor; // The reserve factor of the given market (in bps).
    }

    /// @notice Computes and returns the new growth factors associated to a given pool's supply/borrow index & Morpho's peer-to-peer index.
    /// @param _newPoolSupplyIndex The pool's last current supply index.
    /// @param _newPoolBorrowIndex The pool's last current borrow index.
    /// @param _lastPoolIndexes The pool's last stored indexes.
    /// @param _p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @param _reserveFactor The reserve factor of the given market.
    /// @return growthFactors_ The pool's indexes growth factor (in wad).
    function computeGrowthFactors(
        uint256 _newPoolSupplyIndex,
        uint256 _newPoolBorrowIndex,
        Types.PoolIndexes memory _lastPoolIndexes,
        uint256 _p2pIndexCursor,
        uint256 _reserveFactor
    ) internal pure returns (GrowthFactors memory growthFactors_) {
        growthFactors_.poolSupplyGrowthFactor = _newPoolSupplyIndex.rayDiv(
            _lastPoolIndexes.poolSupplyIndex
        );
        growthFactors_.poolBorrowGrowthFactor = _newPoolBorrowIndex.rayDiv(
            _lastPoolIndexes.poolBorrowIndex
        );

        if (growthFactors_.poolSupplyGrowthFactor <= growthFactors_.poolBorrowGrowthFactor) {
            uint256 p2pGrowthFactor = PercentageMath.percentAvg(
                growthFactors_.poolBorrowGrowthFactor,
                growthFactors_.poolSupplyGrowthFactor,
                _p2pIndexCursor
            );

            growthFactors_.p2pSupplyGrowthFactor =
                p2pGrowthFactor -
                (p2pGrowthFactor - growthFactors_.poolSupplyGrowthFactor).percentMul(
                    _reserveFactor
                );
            growthFactors_.p2pBorrowGrowthFactor =
                p2pGrowthFactor +
                (growthFactors_.poolBorrowGrowthFactor - p2pGrowthFactor).percentMul(
                    _reserveFactor
                );
        } else {
            // The case poolSupplyGrowthFactor > poolBorrowGrowthFactor happens because someone sent underlying tokens to the
            // cToken contract: the peer-to-peer growth factors are set to the pool borrow growth factor.
            growthFactors_.p2pSupplyGrowthFactor = growthFactors_.poolBorrowGrowthFactor;
            growthFactors_.p2pBorrowGrowthFactor = growthFactors_.poolBorrowGrowthFactor;
        }
    }

    /// @notice Computes and returns the new peer-to-peer supply index of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return newP2PSupplyIndex_ The updated peer-to-peer index.
    function computeP2PSupplyIndex(P2PIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex_)
    {
        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PSupplyIndex_ = _params.lastP2PIndex.rayMul(_params.p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                _params.p2pDelta.wadToRay().rayMul(_params.lastPoolIndex).rayDiv(
                    _params.p2pAmount.wadToRay().rayMul(_params.lastP2PIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PSupplyIndex_ = _params.lastP2PIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(_params.p2pGrowthFactor) +
                    shareOfTheDelta.rayMul(_params.poolGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the new peer-to-peer borrow index of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return newP2PBorrowIndex_ The updated peer-to-peer index.
    function computeP2PBorrowIndex(P2PIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PBorrowIndex_)
    {
        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PBorrowIndex_ = _params.lastP2PIndex.rayMul(_params.p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                _params.p2pDelta.wadToRay().rayMul(_params.lastPoolIndex).rayDiv(
                    _params.p2pAmount.wadToRay().rayMul(_params.lastP2PIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PBorrowIndex_ = _params.lastP2PIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(_params.p2pGrowthFactor) +
                    shareOfTheDelta.rayMul(_params.poolGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the peer-to-peer supply rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per year.
    function computeP2PSupplyRatePerYear(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pSupplyRate)
    {
        p2pSupplyRate =
            _params.p2pRate -
            ((_params.p2pRate - _params.poolRate) * _params.reserveFactor) /
            MAX_BASIS_POINTS;

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = Math.min(
                _params.p2pDelta.wadToRay().rayMul(_params.poolIndex).rayDiv(
                    _params.p2pAmount.wadToRay().rayMul(_params.p2pIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            p2pSupplyRate =
                p2pSupplyRate.rayMul(WadRayMath.RAY - shareOfTheDelta) +
                _params.poolRate.rayMul(shareOfTheDelta);
        }
    }

    /// @notice Computes and returns the peer-to-peer borrow rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pBorrowRate The peer-to-peer borrow rate per year.
    function computeP2PBorrowRatePerYear(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pBorrowRate)
    {
        p2pBorrowRate =
            _params.p2pRate +
            ((_params.poolRate - _params.p2pRate) * _params.reserveFactor) /
            MAX_BASIS_POINTS;

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = Math.min(
                _params.p2pDelta.wadToRay().rayMul(_params.poolIndex).rayDiv(
                    _params.p2pAmount.wadToRay().rayMul(_params.p2pIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            p2pBorrowRate =
                p2pBorrowRate.rayMul(WadRayMath.RAY - shareOfTheDelta) +
                _params.poolRate.rayMul(shareOfTheDelta);
        }
    }
}
