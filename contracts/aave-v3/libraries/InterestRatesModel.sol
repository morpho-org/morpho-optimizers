// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

import "../interfaces/aave/IPool.sol";

import "./Types.sol";

library InterestRatesModel {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    /// ERRORS ///

    // Thrown when percentage is above 100%.
    error PercentageTooHigh();

    /// STRUCTS ///

    struct P2PRateComputeParams {
        uint256 poolRate; // The pool's index growth factor (in wad).
        uint256 p2pRate; // Morpho peer-to-peer's median index growth factor (in wad).
        uint256 poolIndex; // The pool's last stored index (in ray).
        uint256 p2pIndex; // Morpho's last stored peer-to-peer index (in ray).
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
        uint256 reserveFactor; // The reserve factor of the given market (in bps).
    }

    function computeP2PIndexes(Types.P2PIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        // Compute pool growth factors
        Types.GrowthFactors memory growthFactors = InterestRatesModel.computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolSupplyIndex,
            _params.lastPoolBorrowIndex,
            _params.p2pIndexCursor,
            _params.reserveFactor
        );
        newP2PSupplyIndex = computeP2PIndex(
            growthFactors.poolSupplyGrowthFactor,
            growthFactors.p2pSupplyGrowthFactor,
            _params.lastPoolSupplyIndex,
            _params.lastP2PSupplyIndex,
            _params.delta.p2pSupplyDelta,
            _params.delta.p2pSupplyAmount
        );
        newP2PBorrowIndex = computeP2PIndex(
            growthFactors.poolBorrowGrowthFactor,
            growthFactors.p2pBorrowGrowthFactor,
            _params.lastPoolBorrowIndex,
            _params.lastP2PBorrowIndex,
            _params.delta.p2pBorrowDelta,
            _params.delta.p2pBorrowAmount
        );
    }

    /// @notice Computes and returns the new growth factors associated to a given pool's supply/borrow index & Morpho's peer-to-peer index.
    /// @param _newPoolSupplyIndex The pool's current supply index.
    /// @param _newPoolBorrowIndex The pool's current borrow index.
    /// @param _lastPoolSupplyIndex The pool's last supply index.
    /// @param _lastPoolBorrowIndex The pool's last borrow index.
    /// @param _p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @param _reserveFactor The reserve factor of the given market.
    /// @return growthFactors The market's indexes growth factors (in ray).
    function computeGrowthFactors(
        uint256 _newPoolSupplyIndex,
        uint256 _newPoolBorrowIndex,
        uint256 _lastPoolSupplyIndex,
        uint256 _lastPoolBorrowIndex,
        uint256 _p2pIndexCursor,
        uint256 _reserveFactor
    ) internal pure returns (Types.GrowthFactors memory growthFactors) {
        growthFactors.poolSupplyGrowthFactor = _newPoolSupplyIndex.rayDiv(_lastPoolSupplyIndex);
        growthFactors.poolBorrowGrowthFactor = _newPoolBorrowIndex.rayDiv(_lastPoolBorrowIndex);

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
            // The case poolSupplyGrowthFactor > poolBorrowGrowthFactor happens because someone has done a flashloan on Aave:
            // the peer-to-peer growth factors are set to the pool borrow growth factor.
            growthFactors.p2pSupplyGrowthFactor = growthFactors.poolBorrowGrowthFactor;
            growthFactors.p2pBorrowGrowthFactor = growthFactors.poolBorrowGrowthFactor;
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
            newP2PIndex_ = _lastP2PIndex.rayMul(_p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                _p2pDelta.wadToRay().rayMul(_lastPoolIndex).rayDiv(
                    _p2pAmount.wadToRay().rayMul(_lastP2PIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PIndex_ = _lastP2PIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(_p2pGrowthFactor) +
                    shareOfTheDelta.rayMul(_poolGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the peer-to-peer supply rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per year (in ray).
    function computeP2PSupplyRatePerYear(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pSupplyRate)
    {
        p2pSupplyRate = computeP2PRatePerYear(
            _params,
            _params.p2pRate - (_params.p2pRate - _params.poolRate).percentMul(_params.reserveFactor)
        );
    }

    /// @notice Computes and returns the peer-to-peer borrow rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pBorrowRate The peer-to-peer borrow rate per year (in ray).
    function computeP2PBorrowRatePerYear(P2PRateComputeParams memory _params)
        internal
        pure
        returns (uint256 p2pBorrowRate)
    {
        p2pBorrowRate = computeP2PRatePerYear(
            _params,
            _params.p2pRate + (_params.poolRate - _params.p2pRate).percentMul(_params.reserveFactor)
        );
    }

    /// @notice Computes and returns the peer-to-peer supply rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per year (in ray).
    function computeP2PRatePerYear(P2PRateComputeParams memory _params, uint256 p2pRate)
        internal
        pure
        returns (uint256)
    {
        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = Math.min(
                _params.p2pDelta.wadToRay().rayMul(_params.poolIndex).rayDiv(
                    _params.p2pAmount.wadToRay().rayMul(_params.p2pIndex)
                ),
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            p2pRate =
                p2pRate.rayMul(WadRayMath.RAY - shareOfTheDelta) +
                _params.poolRate.rayMul(shareOfTheDelta);
        }
        return p2pRate;
    }

    /// @notice Returns the current pool indexes.
    /// @param pool The lending pool.
    /// @param _underlyingToken The address of the underlying token.
    /// @return poolSupplyIndex The pool supply index.
    /// @return poolBorrowIndex The pool borrow index.
    function getPoolIndexes(IPool pool, address _underlyingToken)
        internal
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        poolSupplyIndex = pool.getReserveNormalizedIncome(_underlyingToken);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(_underlyingToken);
    }
}
