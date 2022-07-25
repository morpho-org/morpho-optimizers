// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./RatesLens.sol";

/// @title MarketsLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol markets.
abstract contract MarketsLens is RatesLens {
    using WadRayMath for uint256;

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
        return morpho.getMarketsCreated();
    }

    /// @notice For a given market, returns the average supply/borrow rates and amounts of underlying asset supplied and borrowed through Morpho, on the underlying pool and matched peer-to-peer.
    /// @dev The returned values are not updated.
    /// @param _poolTokenAddress The address of the market of which to get main data.
    /// @return avgSupplyRatePerYear The average supply rate experienced on the given market.
    /// @return avgBorrowRatePerYear The average borrow rate experienced on the given market.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getMainMarketData(address _poolTokenAddress)
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
            _poolTokenAddress
        );
        (avgBorrowRatePerYear, p2pBorrowAmount, poolBorrowAmount) = getAverageBorrowRatePerYear(
            _poolTokenAddress
        );
    }

    /// @notice Returns non-updated indexes, the block at which they were last updated and the total deltas of a given market.
    /// @param _poolTokenAddress The address of the market of which to get advanced data.
    /// @return p2pSupplyIndex The peer-to-peer supply index of the given market (in ray).
    /// @return p2pBorrowIndex The peer-to-peer borrow index of the given market (in ray).
    /// @return poolSupplyIndex The pool supply index of the given market (in ray).
    /// @return poolBorrowIndex The pool borrow index of the given market (in ray).
    /// @return lastUpdateTimestamp The block number at which pool indexes were last updated.
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
            uint32 lastUpdateTimestamp,
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta
        )
    {
        (p2pSupplyIndex, p2pBorrowIndex, poolSupplyIndex, poolBorrowIndex) = getIndexes(
            _poolTokenAddress
        );

        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        p2pSupplyDelta = delta.p2pSupplyDelta.rayMul(poolSupplyIndex);
        p2pBorrowDelta = delta.p2pBorrowDelta.rayMul(poolBorrowIndex);

        Types.PoolIndexes memory poolIndexes = morpho.poolIndexes(_poolTokenAddress);
        lastUpdateTimestamp = poolIndexes.lastUpdateTimestamp;
    }

    /// @notice Returns market's configuration.
    /// @return underlying The underlying token address.
    /// @return isCreated Whether the market is created or not.
    /// @return p2pDisabled Whether user are put in peer-to-peer or not.
    /// @return isPaused Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
    /// @return isPartiallyPaused Whether the market is partially paused or not (only supply and borrow are frozen).
    /// @return reserveFactor The reserve factor applied to this market.
    /// @return p2pIndexCursor The p2p index cursor applied to this market.
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
            uint16 p2pIndexCursor
        )
    {
        underlying = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();

        Types.MarketStatus memory marketStatus = morpho.marketStatus(_poolTokenAddress);
        isCreated = marketStatus.isCreated;
        p2pDisabled = morpho.p2pDisabled(_poolTokenAddress);
        isPaused = marketStatus.isPaused;
        isPartiallyPaused = marketStatus.isPartiallyPaused;

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
        reserveFactor = marketParams.reserveFactor;
        p2pIndexCursor = marketParams.p2pIndexCursor;
    }

    /// PUBLIC ///

    /// @notice Computes and returns the total distribution of supply for a given market.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function getTotalMarketSupply(address _poolTokenAddress)
        public
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount)
    {
        (, p2pSupplyAmount, poolSupplyAmount) = _getTotalMarketSupply(_poolTokenAddress);
    }

    /// @notice Computes and returns the total distribution of borrows for a given market.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getTotalMarketBorrow(address _poolTokenAddress)
        public
        view
        returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount)
    {
        (, p2pBorrowAmount, poolBorrowAmount) = _getTotalMarketBorrow(_poolTokenAddress);
    }

    /// INTERNAL ///

    /// @notice Computes and returns the total distribution of supply for a given market.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function _getTotalMarketSupply(address _poolTokenAddress)
        public
        view
        returns (
            address underlyingToken,
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount
        )
    {
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        (underlyingToken, p2pSupplyIndex, poolSupplyIndex, ) = _getCurrentP2PSupplyIndex(
            _poolTokenAddress
        );

        (p2pSupplyAmount, poolSupplyAmount) = _getMarketSupply(
            _poolTokenAddress,
            p2pSupplyIndex,
            poolSupplyIndex
        );
    }

    /// @notice Computes and returns the total distribution of borrows for a given market.
    /// @param _poolTokenAddress The address of the market to check.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function _getTotalMarketBorrow(address _poolTokenAddress)
        public
        view
        returns (
            address underlyingToken,
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount
        )
    {
        uint256 p2pBorrowIndex;
        uint256 poolBorrowIndex;
        (underlyingToken, p2pBorrowIndex, , poolBorrowIndex) = _getCurrentP2PBorrowIndex(
            _poolTokenAddress
        );

        DataTypes.ReserveData memory reserve = pool.getReserveData(underlyingToken);

        (p2pBorrowAmount, poolBorrowAmount) = _getMarketBorrow(
            reserve,
            p2pBorrowIndex,
            poolBorrowIndex
        );
    }
}
