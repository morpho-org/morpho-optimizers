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
    /// @return currentP2PSupplyIndex The updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolToken)
        public
        view
        returns (uint256 currentP2PSupplyIndex)
    {
        (currentP2PSupplyIndex, , ) = _getCurrentP2PSupplyIndex(_poolToken);
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolToken The address of the market.
    /// @return currentP2PBorrowIndex The updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolToken)
        public
        view
        returns (uint256 currentP2PBorrowIndex)
    {
        (currentP2PBorrowIndex, , ) = _getCurrentP2PBorrowIndex(_poolToken);
    }

    /// @notice Returns the optionally updated pool & peer-to-peer indexes.
    /// @param _poolToken The address of the market.
    /// @param _getUpdatedIndexes Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return newP2PSupplyIndex The updated peer-to-peer supply index.
    /// @return newP2PBorrowIndex The updated peer-to-peer borrow index.
    /// @return newPoolSupplyIndex The updated pool supply index.
    /// @return newPoolBorrowIndex The updated pool borrow index.
    function getIndexes(address _poolToken, bool _getUpdatedIndexes)
        public
        view
        returns (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        )
    {
        if (!_getUpdatedIndexes) {
            ICToken cToken = ICToken(_poolToken);

            newPoolSupplyIndex = cToken.exchangeRateStored();
            newPoolBorrowIndex = cToken.borrowIndex();
        } else {
            (newPoolSupplyIndex, newPoolBorrowIndex) = getCurrentPoolIndexes(_poolToken);
        }

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);
        if (!_getUpdatedIndexes || block.number == lastPoolIndexes.lastUpdateBlockNumber) {
            newP2PSupplyIndex = morpho.p2pSupplyIndex(_poolToken);
            newP2PBorrowIndex = morpho.p2pBorrowIndex(_poolToken);
        } else {
            Types.Delta memory delta = morpho.deltas(_poolToken);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor,
                marketParams.reserveFactor
            );

            newP2PSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
                InterestRatesModel.P2PSupplyIndexComputeParams({
                    poolSupplyGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                    p2pSupplyGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                    lastPoolSupplyIndex: lastPoolIndexes.lastSupplyPoolIndex,
                    lastP2PSupplyIndex: morpho.p2pSupplyIndex(_poolToken),
                    p2pSupplyDelta: delta.p2pSupplyDelta,
                    p2pSupplyAmount: delta.p2pSupplyAmount
                })
            );
            newP2PBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
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
    /// @return currentPoolSupplyIndex The supply index.
    /// @return currentPoolBorrowIndex The borrow index.
    function getCurrentPoolIndexes(address _poolToken)
        public
        view
        returns (uint256 currentPoolSupplyIndex, uint256 currentPoolBorrowIndex)
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

        currentPoolSupplyIndex = totalSupply > 0
            ? (cashPrior + totalBorrowsNew - totalReservesNew).div(totalSupply)
            : cToken.initialExchangeRateMantissa();
        currentPoolBorrowIndex = simpleInterestFactor.mul(borrowIndexPrior) + borrowIndexPrior;
    }

    /// INTERNAL ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolToken The address of the market.
    /// @return currentP2PSupplyIndex The updated peer-to-peer supply index.
    /// @return currentPoolSupplyIndex The updated pool supply index.
    /// @return currentPoolBorrowIndex The updated pool borrow index.
    function _getCurrentP2PSupplyIndex(address _poolToken)
        internal
        view
        returns (
            uint256 currentP2PSupplyIndex,
            uint256 currentPoolSupplyIndex,
            uint256 currentPoolBorrowIndex
        )
    {
        (currentPoolSupplyIndex, currentPoolBorrowIndex) = getCurrentPoolIndexes(_poolToken);

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);
        if (block.number == lastPoolIndexes.lastUpdateBlockNumber)
            currentP2PSupplyIndex = morpho.p2pSupplyIndex(_poolToken);
        else {
            Types.Delta memory delta = morpho.deltas(_poolToken);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                currentPoolSupplyIndex,
                currentPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor,
                marketParams.reserveFactor
            );

            currentP2PSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
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
    /// @return currentP2PBorrowIndex The updated peer-to-peer supply index.
    /// @return currentPoolSupplyIndex The updated pool supply index.
    /// @return currentPoolBorrowIndex The updated pool borrow index.
    function _getCurrentP2PBorrowIndex(address _poolToken)
        internal
        view
        returns (
            uint256 currentP2PBorrowIndex,
            uint256 currentPoolSupplyIndex,
            uint256 currentPoolBorrowIndex
        )
    {
        (currentPoolSupplyIndex, currentPoolBorrowIndex) = getCurrentPoolIndexes(_poolToken);

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);
        if (block.number == lastPoolIndexes.lastUpdateBlockNumber)
            currentP2PBorrowIndex = morpho.p2pBorrowIndex(_poolToken);
        else {
            Types.Delta memory delta = morpho.deltas(_poolToken);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                currentPoolSupplyIndex,
                currentPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor,
                marketParams.reserveFactor
            );

            currentP2PBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
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
