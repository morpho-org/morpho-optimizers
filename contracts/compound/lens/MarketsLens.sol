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
    /// @return marketsCreated_ The list of market addresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated_) {
        return morpho.getAllMarkets();
    }

    /// @notice For a given market, returns the average supply/borrow rates and amounts of underlying asset supplied and borrowed through Morpho, on the underlying pool and matched peer-to-peer.
    /// @dev The returned values are not updated.
    /// @param _poolTokenAddress The address of the market of which to get main data.
    /// @return avgSupplyRatePerBlock The average supply rate experienced on the given market.
    /// @return avgBorrowRatePerBlock The average borrow rate experienced on the given market.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, including the supply delta (in underlying).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, including the borrow delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, without the supply delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, without the borrow delta (in underlying).
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
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = getIndexes(_poolTokenAddress, false);
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        ICToken poolToken = ICToken(_poolTokenAddress);

        p2pSupplyAmount = delta.p2pSupplyAmount.mul(p2pSupplyIndex);
        p2pBorrowAmount = delta.p2pBorrowAmount.mul(p2pBorrowIndex);
        poolSupplyAmount = poolToken.balanceOf(address(morpho)).mul(poolSupplyIndex);
        poolBorrowAmount = poolToken.borrowBalanceStored(address(morpho)).mul(poolBorrowIndex);

        avgSupplyRatePerBlock = getAverageSupplyRatePerBlock(_poolTokenAddress);
        avgBorrowRatePerBlock = getAverageBorrowRatePerBlock(_poolTokenAddress);
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
    /// @return underlying_ The underlying token address.
    /// @return isCreated_ Whether the market is created or not.
    /// @return p2pDisabled_ Whether user are put in peer-to-peer or not.
    /// @return isPaused_ Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
    /// @return isPartiallyPaused_ Whether the market is partially paused or not (only supply and borrow are frozen).
    /// @return reserveFactor_ The reserve factor applied to this market.
    /// @return p2pIndexCursor_ The p2p index cursor applied to this market.
    /// @return collateralFactor_ The pool collateral factor also used by Morpho.
    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (
            address underlying_,
            bool isCreated_,
            bool p2pDisabled_,
            bool isPaused_,
            bool isPartiallyPaused_,
            uint16 reserveFactor_,
            uint16 p2pIndexCursor_,
            uint256 collateralFactor_
        )
    {
        underlying_ = _poolTokenAddress == morpho.cEth()
            ? morpho.wEth()
            : ICToken(_poolTokenAddress).underlying();

        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        isCreated_ = marketStatus.isCreated;
        p2pDisabled_ = morpho.p2pDisabled(_poolTokenAddress);
        isPaused_ = marketStatus.isPaused;
        isPartiallyPaused_ = marketStatus.isPartiallyPaused;

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
        reserveFactor_ = marketParams.reserveFactor;
        p2pIndexCursor_ = marketParams.p2pIndexCursor;

        (, collateralFactor_, ) = comptroller.markets(_poolTokenAddress);
    }
}
