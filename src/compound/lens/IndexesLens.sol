// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "../libraries/InterestRatesModel.sol";

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    using CompoundMath for uint256;

    /// EXTERNAL ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The virtually updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolToken)
        external
        view
        returns (uint256 p2pSupplyIndex)
    {
        (, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        p2pSupplyIndex = indexes.p2pSupplyIndex;
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return p2pBorrowIndex The virtually updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolToken)
        external
        view
        returns (uint256 p2pBorrowIndex)
    {
        (, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        p2pBorrowIndex = indexes.p2pBorrowIndex;
    }

    /// @notice Returns the most up-to-date or virtually updated peer-to-peer and pool indexes.
    /// @dev If not virtually updated, the indexes returned are those used by Morpho for non-updated markets during the liquidity check.
    /// @param _poolToken The address of the market.
    /// @param _updated Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return indexes The given market's virtually updated indexes.
    function getIndexes(address _poolToken, bool _updated)
        external
        view
        returns (Types.Indexes memory indexes)
    {
        (, indexes) = _getIndexes(_poolToken, _updated);
    }

    /// @notice Returns the virtually updated pool indexes of a given market.
    /// @dev Mimicks `CToken.accrueInterest`'s calculations, without writing to the storage.
    /// @param _poolToken The address of the market.
    /// @return poolSupplyIndex The supply index.
    /// @return poolBorrowIndex The borrow index.
    function getCurrentPoolIndexes(address _poolToken)
        external
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        (poolSupplyIndex, poolBorrowIndex, ) = _accruePoolInterests(ICToken(_poolToken));
    }

    /// INTERNAL ///

    struct PoolInterestsVars {
        uint256 cash;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 reserveFactorMantissa;
    }

    /// @notice Returns the most up-to-date or virtually updated peer-to-peer and pool indexes.
    /// @dev If not virtually updated, the indexes returned are those used by Morpho for non-updated markets during the liquidity check.
    /// @param _poolToken The address of the market.
    /// @param _updated Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return delta The given market's deltas.
    /// @return indexes The given market's updated indexes.
    function _getIndexes(address _poolToken, bool _updated)
        internal
        view
        returns (Types.Delta memory delta, Types.Indexes memory indexes)
    {
        delta = morpho.deltas(_poolToken);
        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);

        if (!_updated) {
            indexes.poolSupplyIndex = ICToken(_poolToken).exchangeRateStored();
            indexes.poolBorrowIndex = ICToken(_poolToken).borrowIndex();
        } else {
            (indexes.poolSupplyIndex, indexes.poolBorrowIndex, ) = _accruePoolInterests(
                ICToken(_poolToken)
            );
        }

        (indexes.p2pSupplyIndex, indexes.p2pBorrowIndex, ) = _computeP2PIndexes(
            _poolToken,
            _updated,
            indexes.poolSupplyIndex,
            indexes.poolBorrowIndex,
            delta,
            lastPoolIndexes
        );
    }

    /// @notice Returns the virtually updated pool indexes of a given market.
    /// @dev Mimicks `CToken.accrueInterest`'s calculations, without writing to the storage.
    /// @param _poolToken The address of the market.
    /// @return poolSupplyIndex The supply index.
    /// @return poolBorrowIndex The borrow index.
    function _accruePoolInterests(ICToken _poolToken)
        internal
        view
        returns (
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex,
            PoolInterestsVars memory vars
        )
    {
        poolBorrowIndex = _poolToken.borrowIndex();
        vars.cash = _poolToken.getCash();
        vars.totalBorrows = _poolToken.totalBorrows();
        vars.totalReserves = _poolToken.totalReserves();
        vars.reserveFactorMantissa = _poolToken.reserveFactorMantissa();

        uint256 accrualBlockNumberPrior = _poolToken.accrualBlockNumber();
        if (block.number == accrualBlockNumberPrior) {
            poolSupplyIndex = _poolToken.exchangeRateStored();

            return (poolSupplyIndex, poolBorrowIndex, vars);
        }

        uint256 borrowRateMantissa = _poolToken.borrowRatePerBlock();
        require(borrowRateMantissa <= 0.0005e16, "borrow rate is absurdly high");

        uint256 simpleInterestFactor = borrowRateMantissa *
            (block.number - accrualBlockNumberPrior);
        uint256 interestAccumulated = simpleInterestFactor.mul(vars.totalBorrows);

        vars.totalBorrows += interestAccumulated;
        vars.totalReserves += vars.reserveFactorMantissa.mul(interestAccumulated);

        poolSupplyIndex = (vars.cash + vars.totalBorrows - vars.totalReserves).div(
            _poolToken.totalSupply()
        );
        poolBorrowIndex += simpleInterestFactor.mul(poolBorrowIndex);
    }

    /// @notice Returns the most up-to-date or virtually updated peer-to-peer  indexes.
    /// @dev If not virtually updated, the indexes returned are those used by Morpho for non-updated markets during the liquidity check.
    /// @param _poolToken The address of the market.
    /// @param _updated Whether to compute virtually updated peer-to-peer indexes.
    /// @param _poolSupplyIndex The underlying pool supply index.
    /// @param _poolBorrowIndex The underlying pool borrow index.
    /// @param _delta The given market's deltas.
    /// @param _lastPoolIndexes The last pool indexes stored on Morpho.
    /// @return _p2pSupplyIndex The given market's peer-to-peer supply index.
    /// @return _p2pBorrowIndex The given market's peer-to-peer borrow index.
    function _computeP2PIndexes(
        address _poolToken,
        bool _updated,
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex,
        Types.Delta memory _delta,
        Types.LastPoolIndexes memory _lastPoolIndexes
    )
        internal
        view
        returns (
            uint256 _p2pSupplyIndex,
            uint256 _p2pBorrowIndex,
            Types.MarketParameters memory marketParameters
        )
    {
        marketParameters = morpho.marketParameters(_poolToken);

        if (!_updated) {
            return (
                morpho.p2pSupplyIndex(_poolToken),
                morpho.p2pBorrowIndex(_poolToken),
                marketParameters
            );
        }

        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            _poolSupplyIndex,
            _poolBorrowIndex,
            _lastPoolIndexes,
            marketParameters.p2pIndexCursor,
            marketParameters.reserveFactor
        );

        _p2pSupplyIndex = InterestRatesModel.computeP2PIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                lastPoolIndex: _lastPoolIndexes.lastSupplyPoolIndex,
                lastP2PIndex: morpho.p2pSupplyIndex(_poolToken),
                p2pDelta: _delta.p2pSupplyDelta,
                p2pAmount: _delta.p2pSupplyAmount
            })
        );
        _p2pBorrowIndex = InterestRatesModel.computeP2PIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                lastPoolIndex: _lastPoolIndexes.lastBorrowPoolIndex,
                lastP2PIndex: morpho.p2pBorrowIndex(_poolToken),
                p2pDelta: _delta.p2pBorrowDelta,
                p2pAmount: _delta.p2pBorrowAmount
            })
        );
    }
}
