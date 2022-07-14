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
        uint256 poolSupplyGrowthFactor; // Pool supply index growth factor (in wad).
        uint256 poolBorrowGrowthFactor; // Pool borrow index growth factor (in wad).
        uint256 p2pSupplyGrowthFactor; // Peer-to-peer supply index growth factor (in wad).
        uint256 p2pBorrowGrowthFactor; // Peer-to-peer borrow index growth factor (in wad).
    }

    struct P2PSupplyIndexComputeParams {
        uint256 poolSupplyGrowthFactor; // Pool supply index growth factor (in wad).
        uint256 p2pSupplyGrowthFactor; // Peer-to-peer supply index growth factor (in wad).
        uint256 lastP2PSupplyIndex; // Last stored peer-to-peer supply index (in wad).
        uint256 lastPoolSupplyIndex; // Last stored pool supply index (in wad).
        uint256 p2pSupplyDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pSupplyAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
    }

    struct P2PBorrowIndexComputeParams {
        uint256 poolBorrowGrowthFactor; // Pool borrow index growth factor (in wad).
        uint256 p2pBorrowGrowthFactor; // Peer-to-peer borrow index growth factor (in wad).
        uint256 lastP2PBorrowIndex; // Last stored peer-to-peer borrow index (in wad).
        uint256 lastPoolBorrowIndex; // Last stored pool borrow index (in wad).
        uint256 p2pBorrowDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pBorrowAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
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

    /// @notice Computes and returns the new peer-to-peer growth factors.
    /// @param _newPoolSupplyIndex The pool's last current supply index.
    /// @param _newPoolBorrowIndex The pool's last current borrow index.
    /// @param _lastPoolIndexes The pool's last stored indexes.
    /// @param _p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @return growthFactors_ The pool's indexes growth factor (in wad).
    function computeGrowthFactors(
        uint256 _newPoolSupplyIndex,
        uint256 _newPoolBorrowIndex,
        Types.LastPoolIndexes memory _lastPoolIndexes,
        uint16 _p2pIndexCursor,
        uint256 _reserveFactor
    ) internal pure returns (GrowthFactors memory growthFactors_) {
        growthFactors_.poolSupplyGrowthFactor = _newPoolSupplyIndex.div(
            _lastPoolIndexes.lastSupplyPoolIndex
        );
        growthFactors_.poolBorrowGrowthFactor = _newPoolBorrowIndex.div(
            _lastPoolIndexes.lastBorrowPoolIndex
        );

        if (growthFactors_.poolSupplyGrowthFactor <= growthFactors_.poolBorrowGrowthFactor) {
            uint256 p2pGrowthFactor = ((MAX_BASIS_POINTS - _p2pIndexCursor) *
                growthFactors_.poolSupplyGrowthFactor +
                _p2pIndexCursor *
                growthFactors_.poolBorrowGrowthFactor) / MAX_BASIS_POINTS;
            growthFactors_.p2pSupplyGrowthFactor =
                p2pGrowthFactor -
                (_reserveFactor * (p2pGrowthFactor - growthFactors_.poolSupplyGrowthFactor)) /
                MAX_BASIS_POINTS;
            growthFactors_.p2pBorrowGrowthFactor =
                p2pGrowthFactor +
                (_reserveFactor * (growthFactors_.poolBorrowGrowthFactor - p2pGrowthFactor)) /
                MAX_BASIS_POINTS;
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
    function computeP2PSupplyIndex(P2PSupplyIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex_)
    {
        if (_params.p2pSupplyAmount == 0 || _params.p2pSupplyDelta == 0) {
            newP2PSupplyIndex_ = _params.lastP2PSupplyIndex.mul(_params.p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pSupplyDelta.mul(_params.lastPoolSupplyIndex)).div(
                    (_params.p2pSupplyAmount).mul(_params.lastP2PSupplyIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PSupplyIndex_ = _params.lastP2PSupplyIndex.mul(
                (WAD - shareOfTheDelta).mul(_params.p2pSupplyGrowthFactor) +
                    shareOfTheDelta.mul(_params.poolSupplyGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the new peer-to-peer borrow index of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return newP2PBorrowIndex_ The updated peer-to-peer index.
    function computeP2PBorrowIndex(P2PBorrowIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PBorrowIndex_)
    {
        if (_params.p2pBorrowAmount == 0 || _params.p2pBorrowDelta == 0) {
            newP2PBorrowIndex_ = _params.lastP2PBorrowIndex.mul(_params.p2pBorrowGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pBorrowDelta.mul(_params.lastPoolBorrowIndex)).div(
                    (_params.p2pBorrowAmount).mul(_params.lastP2PBorrowIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PBorrowIndex_ = _params.lastP2PBorrowIndex.mul(
                (WAD - shareOfTheDelta).mul(_params.p2pBorrowGrowthFactor) +
                    shareOfTheDelta.mul(_params.poolBorrowGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the raw peer-to-peer rate per block of a market given the pool rates.
    /// @param _poolSupplyRate The pool's supply rate per block.
    /// @param _poolBorrowRate The pool's borrow rate per block.
    /// @param _p2pIndexCursor The market's p2p index cursor.
    /// @return The raw peer-to-peer rate per block, without reserve factor, without delta.
    function computeRawP2PRatePerBlock(
        uint256 _poolSupplyRate,
        uint256 _poolBorrowRate,
        uint256 _p2pIndexCursor
    ) internal pure returns (uint256) {
        return
            ((MAX_BASIS_POINTS - _p2pIndexCursor) *
                _poolSupplyRate +
                _p2pIndexCursor *
                _poolBorrowRate) / MAX_BASIS_POINTS;
    }

    /// @notice Computes and returns the peer-to-peer supply rate per block of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per block.
    function computeP2PSupplyRatePerBlock(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pSupplyRate)
    {
        p2pSupplyRate =
            _params.p2pRate -
            ((_params.p2pRate - _params.poolRate) * _params.reserveFactor) /
            MAX_BASIS_POINTS;

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = CompoundMath.min(
                _params.p2pDelta.mul(_params.poolIndex).div(
                    _params.p2pAmount.mul(_params.p2pIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            p2pSupplyRate =
                p2pSupplyRate.mul(WAD - shareOfTheDelta) +
                _params.poolRate.mul(shareOfTheDelta);
        }
    }

    /// @notice Computes and returns the peer-to-peer borrow rate per block of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pBorrowRate The peer-to-peer borrow rate per block.
    function computeP2PBorrowRatePerBlock(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pBorrowRate)
    {
        p2pBorrowRate =
            _params.p2pRate +
            ((_params.poolRate - _params.p2pRate) * _params.reserveFactor) /
            MAX_BASIS_POINTS;

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = CompoundMath.min(
                _params.p2pDelta.mul(_params.poolIndex).div(
                    _params.p2pAmount.mul(_params.p2pIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            p2pBorrowRate =
                p2pBorrowRate.mul(WAD - shareOfTheDelta) +
                _params.poolRate.mul(shareOfTheDelta);
        }
    }
}
