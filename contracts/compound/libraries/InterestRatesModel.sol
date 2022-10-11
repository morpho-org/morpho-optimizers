// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./CompoundMath.sol";
import "./Types.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library InterestRatesModel {
    using CompoundMath for uint256;

    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis points).
    uint256 public constant WAD = 1e18;

    /// STRUCTS ///

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
    /// @param _newPoolSupplyIndex The pool's current supply index.
    /// @param _newPoolBorrowIndex The pool's current borrow index.
    /// @param _lastPoolSupplyIndex The pool's last stored supply index.
    /// @param _lastPoolSupplyIndex The pool's last stored borrow index.
    /// @param _p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @param _reserveFactor The reserve factor of the given market.
    /// @return growthFactors_ The pool's indexes growth factor (in wad).
    function computeGrowthFactors(
        uint256 _newPoolSupplyIndex,
        uint256 _newPoolBorrowIndex,
        uint256 _lastPoolSupplyIndex,
        uint256 _lastPoolBorrowIndex,
        uint16 _p2pIndexCursor,
        uint256 _reserveFactor
    ) internal pure returns (Types.GrowthFactors memory growthFactors_) {
        growthFactors_.poolSupplyGrowthFactor = _newPoolSupplyIndex.div(_lastPoolSupplyIndex);
        growthFactors_.poolBorrowGrowthFactor = _newPoolBorrowIndex.div(_lastPoolBorrowIndex);

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

    /// @notice Computes and returns the new peer-to-peer index of a market given its parameters.
    /// @param _poolGrowthFactor The pool growth factor.
    /// @param _p2pGrowthFactor The P2P growth factor.
    /// @param _lastPoolIndex The last pool index.
    /// @param _lastP2PIndex The last P2P index.
    /// @param _p2pDelta The last P2P delta.
    /// @param _p2pAmount The last P2P amount.
    /// @return newP2PIndex_ The updated peer-to-peer index (in ray).
    function computeP2PIndex(
        uint256 _poolGrowthFactor,
        uint256 _p2pGrowthFactor,
        uint256 _lastPoolIndex,
        uint256 _lastP2PIndex,
        uint256 _p2pDelta,
        uint256 _p2pAmount
    ) internal pure returns (uint256 newP2PIndex_) {
        if (_p2pAmount == 0 || _p2pDelta == 0) {
            newP2PIndex_ = _lastP2PIndex.mul(_p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                _p2pDelta.mul(_lastPoolIndex).div(_p2pAmount.mul(_lastP2PIndex)),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PIndex_ = _lastP2PIndex.mul(
                (WAD - shareOfTheDelta).mul(_p2pGrowthFactor) +
                    shareOfTheDelta.mul(_poolGrowthFactor)
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
