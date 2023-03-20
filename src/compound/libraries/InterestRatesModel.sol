// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@morpho-dao/morpho-utils/math/CompoundMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";
import "./Types.sol";

library InterestRatesModel {
    using PercentageMath for uint256;
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct GrowthFactors {
        uint256 poolSupplyGrowthFactor; // The pool supply index growth factor (in wad).
        uint256 poolBorrowGrowthFactor; // The pool borrow index growth factor (in wad).
        uint256 p2pSupplyGrowthFactor; // Peer-to-peer supply index growth factor (in wad).
        uint256 p2pBorrowGrowthFactor; // Peer-to-peer borrow index growth factor (in wad).
    }

    struct P2PIndexComputeParams {
        uint256 poolGrowthFactor; // The pool index growth factor (in wad).
        uint256 p2pGrowthFactor; // Morpho's peer-to-peer median index growth factor (in wad).
        uint256 lastPoolIndex; // The last stored pool index (in wad).
        uint256 lastP2PIndex; // The last stored peer-to-peer index (in wad).
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
    }

    struct P2PRateComputeParams {
        uint256 poolRate; // The pool rate per block (in wad).
        uint256 p2pRate; // The peer-to-peer rate per block (in wad).
        uint256 poolIndex; // The last stored pool index (in wad).
        uint256 p2pIndex; // The last stored peer-to-peer index (in wad).
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
        uint16 reserveFactor; // The reserve factor of the given market (in bps).
    }

    /// @notice Computes and returns the new supply/borrow growth factors associated to the given market's pool & peer-to-peer indexes.
    /// @param _newPoolSupplyIndex The current pool supply index.
    /// @param _newPoolBorrowIndex The current pool borrow index.
    /// @param _lastPoolIndexes The last stored pool indexes.
    /// @param _p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @param _reserveFactor The reserve factor of the given market.
    /// @return growthFactors The market's indexes growth factors (in wad).
    function computeGrowthFactors(
        uint256 _newPoolSupplyIndex,
        uint256 _newPoolBorrowIndex,
        Types.LastPoolIndexes memory _lastPoolIndexes,
        uint256 _p2pIndexCursor,
        uint256 _reserveFactor
    ) internal pure returns (GrowthFactors memory growthFactors) {
        growthFactors.poolSupplyGrowthFactor = _newPoolSupplyIndex.div(
            _lastPoolIndexes.lastSupplyPoolIndex
        );
        growthFactors.poolBorrowGrowthFactor = _newPoolBorrowIndex.div(
            _lastPoolIndexes.lastBorrowPoolIndex
        );

        if (growthFactors.poolSupplyGrowthFactor <= growthFactors.poolBorrowGrowthFactor) {
            uint256 p2pGrowthFactor = PercentageMath.weightedAvg(
                growthFactors.poolSupplyGrowthFactor,
                growthFactors.poolBorrowGrowthFactor,
                _p2pIndexCursor
            );

            growthFactors.p2pSupplyGrowthFactor =
                p2pGrowthFactor -
                (p2pGrowthFactor - growthFactors.poolSupplyGrowthFactor).percentMul(_reserveFactor);
            growthFactors.p2pBorrowGrowthFactor =
                p2pGrowthFactor +
                (growthFactors.poolBorrowGrowthFactor - p2pGrowthFactor).percentMul(_reserveFactor);
        } else {
            // The case poolSupplyGrowthFactor > poolBorrowGrowthFactor happens because someone sent underlying tokens to the
            // cToken contract: the peer-to-peer growth factors are set to the pool borrow growth factor.
            growthFactors.p2pSupplyGrowthFactor = growthFactors.poolBorrowGrowthFactor;
            growthFactors.p2pBorrowGrowthFactor = growthFactors.poolBorrowGrowthFactor;
        }
    }

    /// @notice Computes and returns the new peer-to-peer supply/borrow index of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return newP2PIndex The updated peer-to-peer index (in wad).
    function computeP2PIndex(P2PIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PIndex)
    {
        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PIndex = _params.lastP2PIndex.mul(_params.p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.p2pDelta.mul(_params.lastPoolIndex)).div(
                    (_params.p2pAmount).mul(_params.lastP2PIndex)
                ),
                CompoundMath.WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PIndex = _params.lastP2PIndex.mul(
                (CompoundMath.WAD - shareOfTheDelta).mul(_params.p2pGrowthFactor) +
                    shareOfTheDelta.mul(_params.poolGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the peer-to-peer supply rate per block of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per block (in wad).
    function computeP2PSupplyRatePerBlock(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pSupplyRate)
    {
        p2pSupplyRate =
            _params.p2pRate -
            (_params.p2pRate - _params.poolRate).percentMul(_params.reserveFactor);

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = Math.min(
                _params.p2pDelta.mul(_params.poolIndex).div(
                    _params.p2pAmount.mul(_params.p2pIndex)
                ),
                CompoundMath.WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            p2pSupplyRate =
                p2pSupplyRate.mul(CompoundMath.WAD - shareOfTheDelta) +
                _params.poolRate.mul(shareOfTheDelta);
        }
    }

    /// @notice Computes and returns the peer-to-peer borrow rate per block of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pBorrowRate The peer-to-peer borrow rate per block (in wad).
    function computeP2PBorrowRatePerBlock(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pBorrowRate)
    {
        p2pBorrowRate =
            _params.p2pRate +
            (_params.poolRate - _params.p2pRate).percentMul(_params.reserveFactor);

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = Math.min(
                _params.p2pDelta.mul(_params.poolIndex).div(
                    _params.p2pAmount.mul(_params.p2pIndex)
                ),
                CompoundMath.WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            p2pBorrowRate =
                p2pBorrowRate.mul(CompoundMath.WAD - shareOfTheDelta) +
                _params.poolRate.mul(shareOfTheDelta);
        }
    }
}
