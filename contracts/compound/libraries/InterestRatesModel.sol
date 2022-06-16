// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./CompoundMath.sol";
import "./Types.sol";

library InterestRatesModel {
    using CompoundMath for uint256;

    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis points).
    uint256 public constant WAD = 1e18;

    /// STRUCTS ///

    struct GrowthFactors {
        uint256 poolSupplyGrowthFactor; // The pool's supply index growth factor (in wad).
        uint256 poolBorrowGrowthFactor; // The pool's borrow index growth factor (in wad).
        uint256 p2pGrowthFactor; // Morpho peer-to-peer's median index growth factor (in wad).
    }

    struct P2PIndexComputeParams {
        uint256 poolGrowthFactor; // The pool's index growth factor (in wad).
        uint256 p2pGrowthFactor; // Morpho peer-to-peer's median index growth factor (in wad).
        uint112 lastPoolIndex; // The pool's last stored index.
        uint256 lastP2PIndex; // Morpho's last stored peer-to-peer index.
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
        uint16 reserveFactor; // The reserve factor of the given market (in bps).
    }

    struct P2PRateComputeParams {
        uint256 poolRate; // The pool's index growth factor (in wad).
        uint256 p2pRate; // Morpho peer-to-peer's median index growth factor (in wad).
        uint256 poolIndex; // The pool's last stored index.
        uint256 p2pIndex; // Morpho's last stored peer-to-peer index.
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
        uint16 reserveFactor; // The reserve factor of the given market (in bps).
    }

    /// @notice Computes and returns the new growth factors associated to a given pool's supply/borrow index & Morpho's peer-to-peer index.
    /// @param _newPoolSupplyIndex The pool's last current supply index.
    /// @param _newPoolBorrowIndex The pool's last current borrow index.
    /// @param _lastPoolIndexes The pool's last stored indexes.
    /// @param _p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @return growthFactors_ The pool's indexes growth factor (in wad).
    function computeGrowthFactors(
        uint256 _newPoolSupplyIndex,
        uint256 _newPoolBorrowIndex,
        Types.LastPoolIndexes memory _lastPoolIndexes,
        uint16 _p2pIndexCursor
    ) internal pure returns (GrowthFactors memory growthFactors_) {
        growthFactors_.poolSupplyGrowthFactor = _newPoolSupplyIndex.div(
            _lastPoolIndexes.lastSupplyPoolIndex
        );
        growthFactors_.poolBorrowGrowthFactor = _newPoolBorrowIndex.div(
            _lastPoolIndexes.lastBorrowPoolIndex
        );
        growthFactors_.p2pGrowthFactor =
            ((MAX_BASIS_POINTS - _p2pIndexCursor) *
                growthFactors_.poolSupplyGrowthFactor +
                _p2pIndexCursor *
                growthFactors_.poolBorrowGrowthFactor) /
            MAX_BASIS_POINTS;
    }

    /// @notice Computes and returns the new peer-to-peer supply index of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return newP2PSupplyIndex_ The updated peer-to-peer index.
    function computeP2PSupplyIndex(P2PIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex_)
    {
        uint256 p2pSupplyGrowthFactor = _params.p2pGrowthFactor -
            (_params.reserveFactor * (_params.p2pGrowthFactor - _params.poolGrowthFactor)) /
            MAX_BASIS_POINTS;

        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PSupplyIndex_ = _params.lastP2PIndex.mul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pDelta.mul(_params.lastPoolIndex)).div(
                    (_params.p2pAmount).mul(_params.lastP2PIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PSupplyIndex_ = _params.lastP2PIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pSupplyGrowthFactor) +
                    shareOfTheDelta.mul(_params.poolGrowthFactor)
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
        uint256 p2pBorrowGrowthFactor = _params.p2pGrowthFactor +
            (_params.reserveFactor * (_params.poolGrowthFactor - _params.p2pGrowthFactor)) /
            MAX_BASIS_POINTS;

        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PBorrowIndex_ = _params.lastP2PIndex.mul(p2pBorrowGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pDelta.mul(_params.lastPoolIndex)).div(
                    (_params.p2pAmount).mul(_params.lastP2PIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PBorrowIndex_ = _params.lastP2PIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.mul(_params.poolGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the peer-to-peer supply rate per block of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate_ The peer-to-peer supply rate per block.
    function computeP2PSupplyRatePerBlock(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pSupplyRate_)
    {
        p2pSupplyRate_ =
            _params.p2pRate -
            ((_params.p2pRate - _params.poolRate) * _params.reserveFactor) /
            MAX_BASIS_POINTS;

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pDelta.mul(_params.poolIndex)).div(
                    (_params.p2pAmount).mul(_params.p2pIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            p2pSupplyRate_ =
                p2pSupplyRate_.mul(WAD - shareOfTheDelta) +
                _params.poolRate.mul(shareOfTheDelta);
        }
    }

    /// @notice Computes and returns the peer-to-peer borrow rate per block of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pBorrowRate_ The peer-to-peer borrow rate per block.
    function computeP2PBorrowRatePerBlock(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pBorrowRate_)
    {
        p2pBorrowRate_ =
            _params.p2pRate +
            ((_params.poolRate - _params.p2pRate) * _params.reserveFactor) /
            MAX_BASIS_POINTS;

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pDelta.mul(_params.poolIndex)).div(
                    (_params.p2pAmount).mul(_params.p2pIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            p2pBorrowRate_ =
                p2pBorrowRate_.mul(WAD - shareOfTheDelta) +
                _params.poolRate.mul(shareOfTheDelta);
        }
    }
}
