// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/IInterestRatesManager.sol";

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return currentP2PSupplyIndex The updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolToken)
        public
        view
        returns (uint256 currentP2PSupplyIndex)
    {
        (, currentP2PSupplyIndex, , ) = _getSupplyIndexes(_poolToken);
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return currentP2PBorrowIndex The updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolToken)
        public
        view
        returns (uint256 currentP2PBorrowIndex)
    {
        (, currentP2PBorrowIndex, , ) = _getBorrowIndexes(_poolToken);
    }

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function getIndexes(address _poolToken)
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
            _poolToken
        );
    }

    /// INTERNAL ///

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getIndexes(address _poolToken)
        internal
        view
        returns (
            address underlyingToken,
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        Types.Delta memory delta = morpho.deltas(_poolToken);
        Types.Market memory market = morpho.market(_poolToken);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolToken);
        underlyingToken = market.underlyingToken;

        (poolSupplyIndex, poolBorrowIndex) = _getPoolIndexes(market.underlyingToken);

        (p2pSupplyIndex, p2pBorrowIndex) = InterestRatesModel.computeP2PIndexes(
            Types.P2PIndexComputeParams({
                lastP2PSupplyIndex: morpho.p2pSupplyIndex(_poolToken),
                lastP2PBorrowIndex: morpho.p2pBorrowIndex(_poolToken),
                poolSupplyIndex: poolSupplyIndex,
                poolBorrowIndex: poolBorrowIndex,
                lastPoolSupplyIndex: lastPoolIndexes.poolSupplyIndex,
                lastPoolBorrowIndex: lastPoolIndexes.poolBorrowIndex,
                reserveFactor: market.reserveFactor,
                p2pIndexCursor: market.p2pIndexCursor,
                delta: delta
            })
        );
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return market The market from which to compute the peer-to-peer supply index.
    /// @return currentP2PSupplyIndex The updated peer-to-peer supply index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getSupplyIndexes(address _poolToken)
        internal
        view
        returns (
            Types.Market memory market,
            uint256 currentP2PSupplyIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        market = morpho.market(_poolToken);
        Types.Delta memory delta = morpho.deltas(_poolToken);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolToken);

        (poolSupplyIndex, poolBorrowIndex) = _getPoolIndexes(market.underlyingToken);

        Types.GrowthFactors memory growthFactors = InterestRatesModel.computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes.poolSupplyIndex,
            lastPoolIndexes.poolBorrowIndex,
            market.p2pIndexCursor,
            market.reserveFactor
        );

        currentP2PSupplyIndex = InterestRatesModel.computeP2PIndex(
            growthFactors.poolSupplyGrowthFactor,
            growthFactors.p2pSupplyGrowthFactor,
            lastPoolIndexes.poolSupplyIndex,
            morpho.p2pSupplyIndex(_poolToken),
            delta.p2pSupplyDelta,
            delta.p2pSupplyAmount
        );
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return market The market from which to compute the peer-to-peer borrow index.
    /// @return currentP2PBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getBorrowIndexes(address _poolToken)
        internal
        view
        returns (
            Types.Market memory market,
            uint256 currentP2PBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        market = morpho.market(_poolToken);
        Types.Delta memory delta = morpho.deltas(_poolToken);
        Types.PoolIndexes memory lastPoolIndexes = morpho.poolIndexes(_poolToken);

        (poolSupplyIndex, poolBorrowIndex) = _getPoolIndexes(market.underlyingToken);

        Types.GrowthFactors memory growthFactors = InterestRatesModel.computeGrowthFactors(
            poolSupplyIndex,
            poolBorrowIndex,
            lastPoolIndexes.poolSupplyIndex,
            lastPoolIndexes.poolBorrowIndex,
            market.p2pIndexCursor,
            market.reserveFactor
        );

        currentP2PBorrowIndex = InterestRatesModel.computeP2PIndex(
            growthFactors.poolBorrowGrowthFactor,
            growthFactors.p2pBorrowGrowthFactor,
            lastPoolIndexes.poolBorrowIndex,
            morpho.p2pBorrowIndex(_poolToken),
            delta.p2pBorrowDelta,
            delta.p2pBorrowAmount
        );
    }

    function _getPoolIndexes(address _underlying)
        internal
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        IInterestRatesManager interestRatesManager = morpho.interestRatesManager();
        (poolSupplyIndex, poolBorrowIndex) = InterestRatesModel.getPoolIndexes(
            pool,
            _underlying,
            _underlying == interestRatesManager.ST_ETH()
                ? interestRatesManager.ST_ETH_BASE_REBASE_INDEX()
                : 0
        );
    }
}
