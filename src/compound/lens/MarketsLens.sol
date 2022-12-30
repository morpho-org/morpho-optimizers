// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./RatesLens.sol";

/// @title MarketsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol markets.
abstract contract MarketsLens is RatesLens {
    using CompoundMath for uint256;

    /// EXTERNAL ///

    /// @notice Checks if a market is created.
    /// @param _poolToken The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreated(address _poolToken) external view returns (bool) {
        return morpho.marketStatus(_poolToken).isCreated;
    }

    /// @dev Deprecated.
    function isMarketCreatedAndNotPaused(address) external pure returns (bool) {
        return false;
    }

    /// @dev Deprecated.
    function isMarketCreatedAndNotPausedNorPartiallyPaused(address) external pure returns (bool) {
        return false;
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated The list of market addresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated) {
        return morpho.getAllMarkets();
    }

    /// @notice For a given market, returns the average supply/borrow rates and amounts of underlying asset supplied and borrowed through Morpho, on the underlying pool and matched peer-to-peer.
    /// @dev The returned values are not updated.
    /// @param _poolToken The address of the market of which to get main data.
    /// @return avgSupplyRatePerBlock The average supply rate experienced on the given market.
    /// @return avgBorrowRatePerBlock The average borrow rate experienced on the given market.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getMainMarketData(address _poolToken)
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
            _poolToken
        );
        (avgBorrowRatePerBlock, p2pBorrowAmount, poolBorrowAmount) = getAverageBorrowRatePerBlock(
            _poolToken
        );
    }

    /// @notice Returns non-updated indexes, the block at which they were last updated and the total deltas of a given market.
    /// @param _poolToken The address of the market of which to get advanced data.
    /// @return indexes The given market's virtually updated indexes.
    /// @return lastUpdateBlockNumber The block number at which pool indexes were last updated.
    /// @return p2pSupplyDelta The total supply delta (in underlying).
    /// @return p2pBorrowDelta The total borrow delta (in underlying).
    function getAdvancedMarketData(address _poolToken)
        external
        view
        returns (
            Types.Indexes memory indexes,
            uint32 lastUpdateBlockNumber,
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta
        )
    {
        Types.Delta memory delta;
        (delta, indexes) = _getIndexes(_poolToken, false);

        p2pSupplyDelta = delta.p2pSupplyDelta.mul(indexes.poolSupplyIndex);
        p2pBorrowDelta = delta.p2pBorrowDelta.mul(indexes.poolBorrowIndex);

        lastUpdateBlockNumber = morpho.lastPoolIndexes(_poolToken).lastUpdateBlockNumber;
    }

    /// @notice Returns the given market's configuration.
    /// @return underlying The underlying token address.
    /// @return isCreated Whether the market is created or not.
    /// @return p2pDisabled Whether the peer-to-peer market is enabled or not.
    /// @return isPaused Deprecated.
    /// @return isPartiallyPaused Deprecated.
    /// @return reserveFactor The reserve factor applied to this market.
    /// @return p2pIndexCursor The p2p index cursor applied to this market.
    /// @return collateralFactor The pool collateral factor also used by Morpho.
    function getMarketConfiguration(address _poolToken)
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
        underlying = _poolToken == morpho.cEth() ? morpho.wEth() : ICToken(_poolToken).underlying();

        isCreated = morpho.marketStatus(_poolToken).isCreated;
        p2pDisabled = morpho.p2pDisabled(_poolToken);
        isPaused = false;
        isPartiallyPaused = false;

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);
        reserveFactor = marketParams.reserveFactor;
        p2pIndexCursor = marketParams.p2pIndexCursor;

        (, collateralFactor, ) = comptroller.markets(_poolToken);
    }

    /// @notice Returns the given market's pause statuses.
    /// @param _poolToken The address of the market of which to get pause statuses.
    /// @return The market status struct.
    function getMarketPauseStatus(address _poolToken)
        external
        view
        returns (Types.MarketPauseStatus memory)
    {
        return morpho.marketPauseStatus(_poolToken);
    }

    /// PUBLIC ///

    /// @notice Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function getTotalMarketSupply(address _poolToken)
        public
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount)
    {
        (Types.Delta memory delta, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        (p2pSupplyAmount, poolSupplyAmount) = _getMarketSupply(
            _poolToken,
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex,
            delta
        );
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getTotalMarketBorrow(address _poolToken)
        public
        view
        returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount)
    {
        (Types.Delta memory delta, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        (p2pBorrowAmount, poolBorrowAmount) = _getMarketBorrow(
            _poolToken,
            indexes.p2pBorrowIndex,
            indexes.poolBorrowIndex,
            delta
        );
    }
}
