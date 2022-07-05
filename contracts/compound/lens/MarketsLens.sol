// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./RatesLens.sol";

/// @title MarketsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol markets.
abstract contract MarketsLens is RatesLens {
    using CompoundMath for uint256;

    /// EXTERNAL ///

    /// @notice Checks if a market is created.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreated(address _poolTokenAddress) external view returns (bool) {
        return morpho.marketStatus(_poolTokenAddress).isCreated;
    }

    /// @notice Checks if a market is created and not paused.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreatedAndNotPaused(address _poolTokenAddress) external view returns (bool) {
        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        return marketStatus.isCreated && !marketStatus.isPaused;
    }

    /// @notice Checks if a market is created and not paused or partially paused.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return true if the market is created, not paused and not partially paused, otherwise false.
    function isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolTokenAddress)
        external
        view
        returns (bool)
    {
        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        return marketStatus.isCreated && !marketStatus.isPaused && !marketStatus.isPartiallyPaused;
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated The list of market addresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated) {
        return morpho.getAllMarkets();
    }

    /// @notice For a given market, returns the average supply/borrow rates and amounts of underlying asset supplied and borrowed through Morpho, on the underlying pool and matched peer-to-peer.
    /// @dev The returned values are not updated.
    /// @param _poolTokenAddress The address of the market of which to get main data.
    /// @return avgSupplyRatePerBlock The average supply rate experienced on the given market.
    /// @return avgBorrowRatePerBlock The average borrow rate experienced on the given market.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, without the supply delta (in underlying).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, without the borrow delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, including the supply delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, including the borrow delta (in underlying).
    function getMainMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 avgSupplyRatePerBlock,
            uint256 avgBorrowRatePerBlock,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount,
            uint256 poolSupplyAmount,
            uint256 poolBorrowAmount
        )
    {
        (avgSupplyRatePerBlock, p2pSupplyAmount, poolSupplyAmount) = getAverageSupplyRatePerBlock(
            _poolTokenAddress
        );
        (avgBorrowRatePerBlock, p2pBorrowAmount, poolBorrowAmount) = getAverageBorrowRatePerBlock(
            _poolTokenAddress
        );
    }

    /// @notice Returns non-updated indexes, the block at which they were last updated and the total deltas of a given market.
    /// @param _poolTokenAddress The address of the market of which to get advanced data.
    /// @return p2pSupplyIndex The peer-to-peer supply index of the given market (in wad).
    /// @return p2pBorrowIndex The peer-to-peer borrow index of the given market (in wad).
    /// @return poolSupplyIndex The pool supply index of the given market (in wad).
    /// @return poolBorrowIndex The pool borrow index of the given market (in wad).
    /// @return lastUpdateBlockNumber The block number at which pool indexes were last updated.
    /// @return p2pSupplyDelta The total supply delta (in underlying).
    /// @return p2pBorrowDelta The total borrow delta (in underlying).
    function getAdvancedMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex,
            uint32 lastUpdateBlockNumber,
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta
        )
    {
        (p2pSupplyIndex, p2pBorrowIndex, poolSupplyIndex, poolBorrowIndex) = getIndexes(
            _poolTokenAddress,
            false
        );

        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        p2pSupplyDelta = delta.p2pSupplyDelta.mul(poolSupplyIndex);
        p2pBorrowDelta = delta.p2pBorrowDelta.mul(poolBorrowIndex);

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolTokenAddress);
        lastUpdateBlockNumber = lastPoolIndexes.lastUpdateBlockNumber;
    }

    /// @notice Returns market's configuration.
    /// @return underlying The underlying token address.
    /// @return isCreated Whether the market is created or not.
    /// @return p2pDisabled Whether user are put in peer-to-peer or not.
    /// @return isPaused Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
    /// @return isPartiallyPaused Whether the market is partially paused or not (only supply and borrow are frozen).
    /// @return reserveFactor The reserve factor applied to this market.
    /// @return p2pIndexCursor The p2p index cursor applied to this market.
    /// @return collateralFactor The pool collateral factor also used by Morpho.
    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (
            address underlying,
            bool isCreated,
            bool p2pDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint16 reserveFactor,
            uint16 p2pIndexCursor,
            uint256 collateralFactor
        )
    {
        underlying = _poolTokenAddress == morpho.cEth()
            ? morpho.wEth()
            : ICToken(_poolTokenAddress).underlying();

        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        isCreated = marketStatus.isCreated;
        p2pDisabled = morpho.p2pDisabled(_poolTokenAddress);
        isPaused = marketStatus.isPaused;
        isPartiallyPaused = marketStatus.isPartiallyPaused;

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
        reserveFactor = marketParams.reserveFactor;
        p2pIndexCursor = marketParams.p2pIndexCursor;

        (, collateralFactor, ) = comptroller.markets(_poolTokenAddress);
    }

    /// PUBLIC ///

    /// @notice Computes and returns the total distribution of supply for a given market, optionally using virtually updated indexes.
    /// @param _poolTokenAddress The address of the market to check.
    /// @param _computeUpdatedIndexes Whether to compute virtually updated pool & peer-to-peer supply indexes
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, without the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, including the supply delta (in underlying).
    function getTotalMarketSupply(address _poolTokenAddress, bool _computeUpdatedIndexes)
        public
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount)
    {
        (p2pSupplyAmount, poolSupplyAmount) = _computeMarketSupply(
            _poolTokenAddress,
            _computeUpdatedIndexes
        );
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, optionally using virtually updated indexes.
    /// @param _poolTokenAddress The address of the market to check.
    /// @param _computeUpdatedIndexes Whether to compute virtually updated pool & peer-to-peer borrow indexes
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, without the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, including the borrow delta (in underlying).
    function getTotalMarketBorrow(address _poolTokenAddress, bool _computeUpdatedIndexes)
        public
        view
        returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount)
    {
        (p2pBorrowAmount, poolBorrowAmount) = _computeMarketBorrow(
            _poolTokenAddress,
            _computeUpdatedIndexes
        );
    }
}
