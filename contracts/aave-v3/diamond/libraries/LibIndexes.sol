// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {MorphoStorage as S} from "../storage/MorphoStorage.sol";
import {EventsAndErrors as E, Types, PercentageMath, WadRayMath, Math} from "./Libraries.sol";

import {IPool} from "../interfaces/Interfaces.sol";

library LibIndexes {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    /// STRUCTS ///

    struct Params {
        uint256 lastP2PSupplyIndex; // The peer-to-peer supply index at last update.
        uint256 lastP2PBorrowIndex; // The peer-to-peer borrow index at last update.
        uint256 poolSupplyIndex; // The current pool supply index.
        uint256 poolBorrowIndex; // The current pool borrow index.
        uint256 lastPoolSupplyIndex; // The pool supply index at last update.
        uint256 lastPoolBorrowIndex; // The pool borrow index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Types.Delta delta; // The deltas and peer-to-peer amounts.
    }

    /// EVENTS ///

    /// @notice Emitted when the peer-to-peer indexes of a market are updated.
    /// @param _poolToken The address of the market updated.
    /// @param _p2pSupplyIndex The updated supply index from peer-to-peer unit to underlying.
    /// @param _p2pBorrowIndex The updated borrow index from peer-to-peer unit to underlying.
    /// @param _poolSupplyIndex The updated pool supply index.
    /// @param _poolBorrowIndex The updated pool borrow index.
    event P2PIndexesUpdated(
        address indexed _poolToken,
        uint256 _p2pSupplyIndex,
        uint256 _p2pBorrowIndex,
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex
    );

    function m() internal pure returns (MorphoStorage.MarketsLayout storage m) {
        return S.marketsLayout();
    }

    function c() internal pure returns (MorphoStorage.ContractsLayout storage c) {
        return S.contractsLayout();
    }

    /// @notice Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolToken The address of the market to update.
    function updateIndexes(address _poolToken) internal {
        Types.PoolIndexes storage marketPoolIndexes = m().poolIndexes[_poolToken];

        if (block.timestamp == marketPoolIndexes.lastUpdateTimestamp) return;

        Types.Market storage market = m().market[_poolToken];

        address underlyingToken = market.underlyingToken;
        uint256 newPoolSupplyIndex = c().pool.getReserveNormalizedIncome(underlyingToken);
        uint256 newPoolBorrowIndex = c().pool.getReserveNormalizedVariableDebt(underlyingToken);

        Params memory params = Params(
            p2pSupplyIndex[_poolToken],
            p2pBorrowIndex[_poolToken],
            newPoolSupplyIndex,
            newPoolBorrowIndex,
            marketPoolIndexes.poolSupplyIndex,
            marketPoolIndexes.poolBorrowIndex,
            market.reserveFactor,
            market.p2pIndexCursor,
            deltas[_poolToken]
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = computeP2PIndexes(params);

        m().p2pSupplyIndex[_poolToken] = newP2PSupplyIndex;
        m().p2pBorrowIndex[_poolToken] = newP2PBorrowIndex;

        marketPoolIndexes.lastUpdateTimestamp = uint32(block.timestamp);
        marketPoolIndexes.poolSupplyIndex = uint112(newPoolSupplyIndex);
        marketPoolIndexes.poolBorrowIndex = uint112(newPoolBorrowIndex);

        emit E.P2PIndexesUpdated(
            _poolToken,
            newP2PSupplyIndex,
            newP2PBorrowIndex,
            newPoolSupplyIndex,
            newPoolBorrowIndex
        );
    }

    /// INTERNAL ///

    /// @notice Computes and returns new peer-to-peer indexes.
    /// @param _params Computation parameters.
    /// @return newP2PSupplyIndex The updated p2pSupplyIndex.
    /// @return newP2PBorrowIndex The updated p2pBorrowIndex.
    function computeP2PIndexes(Params memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        // Compute pool growth factors

        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.rayDiv(
            _params.lastPoolSupplyIndex
        );
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.rayDiv(
            _params.lastPoolBorrowIndex
        );

        // Compute peer-to-peer growth factors.

        uint256 p2pSupplyGrowthFactor;
        uint256 p2pBorrowGrowthFactor;
        if (poolSupplyGrowthFactor <= poolBorrowGrowthFactor) {
            uint256 p2pGrowthFactor = PercentageMath.weightedAvg(
                poolSupplyGrowthFactor,
                poolBorrowGrowthFactor,
                _params.p2pIndexCursor
            );

            p2pSupplyGrowthFactor =
                p2pGrowthFactor -
                (p2pGrowthFactor - poolSupplyGrowthFactor).percentMul(_params.reserveFactor);
            p2pBorrowGrowthFactor =
                p2pGrowthFactor +
                (poolBorrowGrowthFactor - p2pGrowthFactor).percentMul(_params.reserveFactor);
        } else {
            // The case poolSupplyGrowthFactor > poolBorrowGrowthFactor happens because someone has done a flashloan on Aave:
            // the peer-to-peer growth factors are set to the pool borrow growth factor.
            p2pSupplyGrowthFactor = poolBorrowGrowthFactor;
            p2pBorrowGrowthFactor = poolBorrowGrowthFactor;
        }

        // Compute new peer-to-peer supply index.

        if (_params.delta.p2pSupplyAmount == 0 || _params.delta.p2pSupplyDelta == 0) {
            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(p2pSupplyGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pSupplyDelta.rayMul(_params.lastPoolSupplyIndex)).rayDiv(
                    _params.delta.p2pSupplyAmount.rayMul(_params.lastP2PSupplyIndex)
                ), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PSupplyIndex = _params.lastP2PSupplyIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pSupplyGrowthFactor) +
                    shareOfTheDelta.rayMul(poolSupplyGrowthFactor)
            );
        }

        // Compute new peer-to-peer borrow index.

        if (_params.delta.p2pBorrowAmount == 0 || _params.delta.p2pBorrowDelta == 0) {
            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(p2pBorrowGrowthFactor);
        } else {
            uint256 shareOfTheDelta = Math.min(
                (_params.delta.p2pBorrowDelta.rayMul(_params.lastPoolBorrowIndex)).rayDiv(
                    _params.delta.p2pBorrowAmount.rayMul(_params.lastP2PBorrowIndex)
                ), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            newP2PBorrowIndex = _params.lastP2PBorrowIndex.rayMul(
                (WadRayMath.RAY - shareOfTheDelta).rayMul(p2pBorrowGrowthFactor) +
                    shareOfTheDelta.rayMul(poolBorrowGrowthFactor)
            );
        }
    }
}
