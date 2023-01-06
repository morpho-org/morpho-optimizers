// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "../interfaces/IInterestRatesManager.sol";
import "../interfaces/lido/ILido.sol";

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    using WadRayMath for uint256;

    /// EXTERNAL ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolToken)
        external
        view
        returns (uint256 p2pSupplyIndex)
    {
        (, , Types.Indexes memory indexes) = _getIndexes(_poolToken);

        p2pSupplyIndex = indexes.p2pSupplyIndex;
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolToken)
        external
        view
        returns (uint256 p2pBorrowIndex)
    {
        (, , Types.Indexes memory indexes) = _getIndexes(_poolToken);

        p2pBorrowIndex = indexes.p2pBorrowIndex;
    }

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @return indexes The given market's updated indexes.
    function getIndexes(address _poolToken) external view returns (Types.Indexes memory indexes) {
        (, , indexes) = _getIndexes(_poolToken);
    }

    /// INTERNAL ///

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @return market The given market's market data.
    /// @return delta The given market's deltas.
    /// @return indexes The given market's updated indexes.
    function _getIndexes(address _poolToken)
        internal
        view
        returns (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        )
    {
        market = morpho.market(_poolToken);
        delta = morpho.deltas(_poolToken);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolToken);

        (indexes.poolSupplyIndex, indexes.poolBorrowIndex) = _getPoolIndexes(
            market.underlyingToken
        );

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            indexes.poolSupplyIndex,
            indexes.poolBorrowIndex,
            lastPoolIndexes,
            market.p2pIndexCursor,
            market.reserveFactor
        );

        indexes.p2pSupplyIndex = InterestRatesModel.computeP2PIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolSupplyIndex,
                lastP2PIndex: morpho.p2pSupplyIndex(_poolToken),
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount
            })
        );
        indexes.p2pBorrowIndex = InterestRatesModel.computeP2PIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolBorrowIndex,
                lastP2PIndex: morpho.p2pBorrowIndex(_poolToken),
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount
            })
        );
    }

    /// @notice Returns the current pool indexes.
    /// @param _underlyingToken The address of the underlying token.
    /// @return poolSupplyIndex The pool supply index.
    /// @return poolBorrowIndex The pool borrow index.
    function _getPoolIndexes(address _underlyingToken)
        internal
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        poolSupplyIndex = pool.getReserveNormalizedIncome(_underlyingToken);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(_underlyingToken);

        if (_underlyingToken == ST_ETH) {
            uint256 rebaseIndex = ILido(ST_ETH).getPooledEthByShares(WadRayMath.RAY);

            poolSupplyIndex = poolSupplyIndex.rayMul(rebaseIndex).rayDiv(ST_ETH_BASE_REBASE_INDEX);
            poolBorrowIndex = poolBorrowIndex.rayMul(rebaseIndex).rayDiv(ST_ETH_BASE_REBASE_INDEX);
        }
    }
}
