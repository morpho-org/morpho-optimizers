// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/InterestRatesModel.sol";

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    using CompoundMath for uint256;

    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolToken)
        public
        view
        returns (uint256 p2pSupplyIndex)
    {
        (p2pSupplyIndex, , ) = _getCurrentP2PSupplyIndex(_poolToken);
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolToken)
        public
        view
        returns (uint256 p2pBorrowIndex)
    {
        (p2pBorrowIndex, , ) = _getCurrentP2PBorrowIndex(_poolToken);
    }

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @param _getUpdatedIndexes Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return p2pBorrowIndex The updated peer-to-peer borrow index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function getIndexes(address _poolToken, bool _getUpdatedIndexes)
        public
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        if (!_getUpdatedIndexes) {
            ICToken cToken = ICToken(_poolToken);

            poolSupplyIndex = cToken.exchangeRateStored();
            poolBorrowIndex = cToken.borrowIndex();
        } else {
            (poolSupplyIndex, poolBorrowIndex) = getCurrentPoolIndexes(_poolToken);
        }

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);
        if (!_getUpdatedIndexes || block.number == lastPoolIndexes.lastUpdateBlockNumber) {
            p2pSupplyIndex = morpho.p2pSupplyIndex(_poolToken);
            p2pBorrowIndex = morpho.p2pBorrowIndex(_poolToken);
        } else {
            Types.Delta memory delta = morpho.deltas(_poolToken);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                poolSupplyIndex,
                poolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor,
                marketParams.reserveFactor
            );

            p2pSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
                InterestRatesModel.P2PSupplyIndexComputeParams({
                    poolSupplyGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                    p2pSupplyGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                    lastPoolSupplyIndex: lastPoolIndexes.lastSupplyPoolIndex,
                    lastP2PSupplyIndex: morpho.p2pSupplyIndex(_poolToken),
                    p2pSupplyDelta: delta.p2pSupplyDelta,
                    p2pSupplyAmount: delta.p2pSupplyAmount
                })
            );
            p2pBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
                InterestRatesModel.P2PBorrowIndexComputeParams({
                    poolBorrowGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                    p2pBorrowGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                    lastPoolBorrowIndex: lastPoolIndexes.lastBorrowPoolIndex,
                    lastP2PBorrowIndex: morpho.p2pBorrowIndex(_poolToken),
                    p2pBorrowDelta: delta.p2pBorrowDelta,
                    p2pBorrowAmount: delta.p2pBorrowAmount
                })
            );
        }
    }

    /// @dev Returns Compound's updated indexes of a given market.
    /// @param _poolToken The address of the market.
    /// @return poolSupplyIndex The supply index.
    /// @return poolBorrowIndex The borrow index.
    function getCurrentPoolIndexes(address _poolToken)
        public
        view
        returns (uint256 poolSupplyIndex, uint256 poolBorrowIndex)
    {
        ICToken cToken = ICToken(_poolToken);

        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();
        if (block.number == accrualBlockNumberPrior)
            return (cToken.exchangeRateStored(), cToken.borrowIndex());

        // Read the previous values out of storage
        uint256 cashPrior = cToken.getCash();
        uint256 totalSupply = cToken.totalSupply();
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();
        uint256 borrowIndexPrior = cToken.borrowIndex();

        // Calculate the current borrow interest rate
        uint256 borrowRateMantissa = cToken.borrowRatePerBlock();
        require(borrowRateMantissa <= 0.0005e16, "borrow rate is absurdly high");

        uint256 blockDelta = block.number - accrualBlockNumberPrior;

        // Calculate the interest accumulated into borrows and reserves and the current index.
        uint256 simpleInterestFactor = borrowRateMantissa * blockDelta;
        uint256 interestAccumulated = simpleInterestFactor.mul(borrowsPrior);
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 totalReservesNew = cToken.reserveFactorMantissa().mul(interestAccumulated) +
            reservesPrior;

        poolSupplyIndex = totalSupply > 0
            ? (cashPrior + totalBorrowsNew - totalReservesNew).div(totalSupply)
            : cToken.initialExchangeRateMantissa();
        poolBorrowIndex = simpleInterestFactor.mul(borrowIndexPrior) + borrowIndexPrior;
    }

    /// INTERNAL ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return p2pSupplyIndex The updated peer-to-peer supply index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getCurrentP2PSupplyIndex(address _poolToken)
        internal
        view
        returns (
            uint256 p2pSupplyIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        (poolSupplyIndex, poolBorrowIndex) = getCurrentPoolIndexes(_poolToken);

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);
        if (block.number == lastPoolIndexes.lastUpdateBlockNumber)
            p2pSupplyIndex = morpho.p2pSupplyIndex(_poolToken);
        else {
            Types.Delta memory delta = morpho.deltas(_poolToken);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                poolSupplyIndex,
                poolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor,
                marketParams.reserveFactor
            );

            p2pSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
                InterestRatesModel.P2PSupplyIndexComputeParams({
                    poolSupplyGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                    p2pSupplyGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                    lastPoolSupplyIndex: lastPoolIndexes.lastSupplyPoolIndex,
                    lastP2PSupplyIndex: morpho.p2pSupplyIndex(_poolToken),
                    p2pSupplyDelta: delta.p2pSupplyDelta,
                    p2pSupplyAmount: delta.p2pSupplyAmount
                })
            );
        }
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return p2pBorrowIndex The updated peer-to-peer supply index.
    /// @return poolSupplyIndex The updated pool supply index.
    /// @return poolBorrowIndex The updated pool borrow index.
    function _getCurrentP2PBorrowIndex(address _poolToken)
        internal
        view
        returns (
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        )
    {
        (poolSupplyIndex, poolBorrowIndex) = getCurrentPoolIndexes(_poolToken);

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);
        if (block.number == lastPoolIndexes.lastUpdateBlockNumber)
            p2pBorrowIndex = morpho.p2pBorrowIndex(_poolToken);
        else {
            Types.Delta memory delta = morpho.deltas(_poolToken);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                poolSupplyIndex,
                poolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor,
                marketParams.reserveFactor
            );

            p2pBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
                InterestRatesModel.P2PBorrowIndexComputeParams({
                    poolBorrowGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                    p2pBorrowGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                    lastPoolBorrowIndex: lastPoolIndexes.lastBorrowPoolIndex,
                    lastP2PBorrowIndex: morpho.p2pBorrowIndex(_poolToken),
                    p2pBorrowDelta: delta.p2pBorrowDelta,
                    p2pBorrowAmount: delta.p2pBorrowAmount
                })
            );
        }
    }
}
