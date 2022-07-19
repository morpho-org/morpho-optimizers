// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market.
    /// @return currentP2PSupplyIndex The updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolTokenAddress)
        public
        view
        returns (uint256 currentP2PSupplyIndex)
    {
        (, currentP2PSupplyIndex, , ) = _getCurrentP2PSupplyIndex(_poolTokenAddress);
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market.
    /// @return currentP2PBorrowIndex The updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolTokenAddress)
        public
        view
        returns (uint256 currentP2PBorrowIndex)
    {
        (, currentP2PBorrowIndex, , ) = _getCurrentP2PBorrowIndex(_poolTokenAddress);
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
        (, p2pSupplyIndex, p2pBorrowIndex, poolSupplyIndex, poolBorrowIndex) = _getIndexes(
            _poolTokenAddress
        );
    }

    /// INTERNAL ///

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolTokenAddress The address of the market.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getIndexes(address _poolTokenAddress)
        public
        view
        returns (
            address underlyingToken,
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
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
            marketParams.p2pIndexCursor,
            marketParams.reserveFactor
        );

        p2pSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolSupplyIndex,
                lastP2PIndex: morpho.p2pSupplyIndex(_poolTokenAddress),
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount
            })
        );
        p2pBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolBorrowIndex,
                lastP2PIndex: morpho.p2pBorrowIndex(_poolTokenAddress),
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount
            })
        );
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return currentP2PSupplyIndex The updated peer-to-peer supply index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getCurrentP2PSupplyIndex(address _poolTokenAddress)
        internal
        view
        returns (
            address underlyingToken,
            uint256 currentP2PSupplyIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolTokenAddress);
        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

        underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        poolSupplyIndex = pool.getReserveNormalizedIncome(underlyingToken);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlyingToken);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            marketParams.p2pIndexCursor,
            marketParams.reserveFactor
        );

        currentP2PSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolSupplyIndex,
                lastP2PIndex: morpho.p2pSupplyIndex(_poolTokenAddress),
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount
            })
        );
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return currentP2PBorrowIndex The updated peer-to-peer supply index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getCurrentP2PBorrowIndex(address _poolTokenAddress)
        internal
        view
        returns (
            address underlyingToken,
            uint256 currentP2PBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolTokenAddress);
        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

        underlyingToken = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        poolSupplyIndex = pool.getReserveNormalizedIncome(underlyingToken);
        poolBorrowIndex = pool.getReserveNormalizedVariableDebt(underlyingToken);

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes,
            marketParams.p2pIndexCursor,
            marketParams.reserveFactor
        );

        currentP2PBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                lastPoolIndex: lastPoolIndexes.poolBorrowIndex,
                lastP2PIndex: morpho.p2pBorrowIndex(_poolTokenAddress),
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount
            })
        );
    }
}
