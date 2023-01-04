// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./RatesLens.sol";

/// @title MarketsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol markets.
abstract contract MarketsLens is RatesLens {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    /// EXTERNAL ///

    /// @notice Checks if a market is created.
    /// @param _poolToken The address of the market to check.
    /// @return true if the market is created and not paused, otherwise false.
    function isMarketCreated(address _poolToken) external view returns (bool) {
        return morpho.market(_poolToken).isCreated;
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
        return morpho.getMarketsCreated();
    }

    /// @notice For a given market, returns the average supply/borrow rates and amounts of underlying asset supplied and borrowed through Morpho, on the underlying pool and matched peer-to-peer.
    /// @dev The returned values are not updated.
    /// @param _poolToken The address of the market of which to get main data.
    /// @return avgSupplyRatePerYear The average supply rate experienced on the given market.
    /// @return avgBorrowRatePerYear The average borrow rate experienced on the given market.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getMainMarketData(address _poolToken)
        external
        view
        returns (
            uint256 avgSupplyRatePerYear,
            uint256 avgBorrowRatePerYear,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount,
            uint256 poolSupplyAmount,
            uint256 poolBorrowAmount
        )
    {
        (avgSupplyRatePerYear, p2pSupplyAmount, poolSupplyAmount) = getAverageSupplyRatePerYear(
            _poolToken
        );
        (avgBorrowRatePerYear, p2pBorrowAmount, poolBorrowAmount) = getAverageBorrowRatePerYear(
            _poolToken
        );
    }

    /// @notice Returns non-updated indexes, the block at which they were last updated and the total deltas of a given market.
    /// @param _poolToken The address of the market of which to get advanced data.
    /// @return indexes The given market's updated indexes.
    /// @return lastUpdateTimestamp The timestamp of the block at which pool indexes were last updated.
    /// @return p2pSupplyDelta The total supply delta (in underlying).
    /// @return p2pBorrowDelta The total borrow delta (in underlying).
    function getAdvancedMarketData(address _poolToken)
        external
        view
        returns (
            Types.Indexes memory indexes,
            uint32 lastUpdateTimestamp,
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta
        )
    {
        Types.Delta memory delta;
        (, delta, indexes) = _getIndexes(_poolToken);

        p2pSupplyDelta = delta.p2pSupplyDelta.rayMul(indexes.poolSupplyIndex);
        p2pBorrowDelta = delta.p2pBorrowDelta.rayMul(indexes.poolBorrowIndex);

        lastUpdateTimestamp = morpho.poolIndexes(_poolToken).lastUpdateTimestamp;
    }

    /// @notice Returns the given market's configuration.
    /// @param _poolToken The address of the market of which to get the configuration.
    /// @return underlying The underlying token address.
    /// @return isCreated Whether the market is created or not.
    /// @return isP2PDisabled Whether the peer-to-peer market is enabled or not.
    /// @return isPaused Deprecated.
    /// @return isPartiallyPaused Deprecated.
    /// @return reserveFactor The reserve factor applied to this market.
    /// @return p2pIndexCursor The p2p index cursor applied to this market.
    /// @return loanToValue The ltv of the given market, set by AAVE.
    /// @return liquidationThreshold The liquidation threshold of the given market, set by AAVE.
    /// @return liquidationBonus The liquidation bonus of the given market, set by AAVE.
    /// @return decimals The number of decimals of the underlying token.
    function getMarketConfiguration(address _poolToken)
        external
        view
        returns (
            address underlying,
            bool isCreated,
            bool isP2PDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint16 reserveFactor,
            uint16 p2pIndexCursor,
            uint256 loanToValue,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 decimals
        )
    {
        Types.Market memory market = morpho.market(_poolToken);

        underlying = market.underlyingToken;
        isCreated = market.isCreated;
        isP2PDisabled = market.isP2PDisabled;
        isPaused = false;
        isPartiallyPaused = false;
        reserveFactor = market.reserveFactor;
        p2pIndexCursor = market.p2pIndexCursor;

        (loanToValue, liquidationThreshold, liquidationBonus, decimals, ) = pool
        .getConfiguration(underlying)
        .getParamsMemory();
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

    /// @notice Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function getTotalMarketSupply(address _poolToken)
        external
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount)
    {
        (, p2pSupplyAmount, poolSupplyAmount) = _getTotalMarketSupply(_poolToken);
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getTotalMarketBorrow(address _poolToken)
        external
        view
        returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount)
    {
        (, p2pBorrowAmount, poolBorrowAmount) = _getTotalMarketBorrow(_poolToken);
    }

    /// INTERNAL ///

    /// @notice Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function _getTotalMarketSupply(address _poolToken)
        internal
        view
        returns (
            address underlyingToken,
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount
        )
    {
        (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        ) = _getIndexes(_poolToken);

        underlyingToken = market.underlyingToken;
        (p2pSupplyAmount, poolSupplyAmount) = _getMarketSupply(
            _poolToken,
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex,
            delta
        );
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function _getTotalMarketBorrow(address _poolToken)
        internal
        view
        returns (
            address underlyingToken,
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount
        )
    {
        (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        ) = _getIndexes(_poolToken);

        underlyingToken = market.underlyingToken;
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlyingToken);

        (p2pBorrowAmount, poolBorrowAmount) = _getMarketBorrow(
            reserve,
            indexes.p2pBorrowIndex,
            indexes.poolBorrowIndex,
            delta
        );
    }
}
