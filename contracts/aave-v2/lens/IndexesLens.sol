// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../libraries/InterestRatesModel.sol";
import "../libraries/aave/PercentageMath.sol";
import "../libraries/aave/WadRayMath.sol";

import "./MarketsLens.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is MarketsLens {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market.
    /// @return newP2PSupplyIndex The updated peer-to-peer supply index.
    function getUpdatedP2PSupplyIndex(address _poolTokenAddress) public view returns (uint256) {
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolTokenAddress);
        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

        address underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(underlyingToken);
        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlyingToken);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            marketParams.p2pIndexCursor
        );

        return
            InterestRatesModel.computeP2PSupplyIndex(
                InterestRatesModel.P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                    p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                    lastPoolIndex: lastPoolIndexes.poolSupplyIndex,
                    lastP2PIndex: morpho.p2pSupplyIndex(_poolTokenAddress),
                    p2pDelta: delta.p2pSupplyDelta,
                    p2pAmount: delta.p2pSupplyAmount,
                    reserveFactor: marketParams.reserveFactor
                })
            );
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market.
    /// @return newP2PBorrowIndex The updated peer-to-peer borrow index.
    function getUpdatedP2PBorrowIndex(address _poolTokenAddress) public view returns (uint256) {
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolTokenAddress);
        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

        address underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(underlyingToken);
        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlyingToken);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            marketParams.p2pIndexCursor
        );

        return
            InterestRatesModel.computeP2PBorrowIndex(
                InterestRatesModel.P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                    p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                    lastPoolIndex: lastPoolIndexes.poolBorrowIndex,
                    lastP2PIndex: morpho.p2pBorrowIndex(_poolTokenAddress),
                    p2pDelta: delta.p2pBorrowDelta,
                    p2pAmount: delta.p2pBorrowAmount,
                    reserveFactor: marketParams.reserveFactor
                })
            );
    }

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolTokenAddress The address of the market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function getIndexes(address _poolTokenAddress)
        public
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        address underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        poolSupplyIndex = pool.getReserveNormalizedIncome(underlyingToken);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlyingToken);

        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolTokenAddress);
        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            marketParams.p2pIndexCursor
        );

        p2pSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolSupplyIndex,
                lastP2PIndex: morpho.p2pSupplyIndex(_poolTokenAddress),
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount,
                reserveFactor: marketParams.reserveFactor
            })
        );
        p2pBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolBorrowIndex,
                lastP2PIndex: morpho.p2pBorrowIndex(_poolTokenAddress),
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount,
                reserveFactor: marketParams.reserveFactor
            })
        );
    }
}
