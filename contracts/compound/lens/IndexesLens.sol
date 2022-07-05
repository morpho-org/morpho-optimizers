// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../libraries/InterestRatesModel.sol";
import "../libraries/CompoundMath.sol";

import "./LensStorage.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is LensStorage {
    using CompoundMath for uint256;

    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market.
    /// @return newP2PSupplyIndex The updated peer-to-peer supply index.
    function getCurrentP2PSupplyIndex(address _poolTokenAddress) public view returns (uint256) {
        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolTokenAddress);

        if (block.number == lastPoolIndexes.lastUpdateBlockNumber)
            return morpho.p2pSupplyIndex(_poolTokenAddress);
        else {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = _computeUpdatedPoolIndexes(
                _poolTokenAddress
            );

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor
            );

            return
                InterestRatesModel.computeP2PSupplyIndex(
                    InterestRatesModel.P2PIndexComputeParams({
                        poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                        p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                        lastPoolIndex: lastPoolIndexes.lastSupplyPoolIndex,
                        lastP2PIndex: morpho.p2pSupplyIndex(_poolTokenAddress),
                        p2pDelta: delta.p2pSupplyDelta,
                        p2pAmount: delta.p2pSupplyAmount,
                        reserveFactor: marketParams.reserveFactor
                    })
                );
        }
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market.
    /// @return newP2PBorrowIndex The updated peer-to-peer borrow index.
    function getCurrentP2PBorrowIndex(address _poolTokenAddress) public view returns (uint256) {
        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolTokenAddress);

        if (block.number == lastPoolIndexes.lastUpdateBlockNumber)
            return morpho.p2pBorrowIndex(_poolTokenAddress);
        else {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = _computeUpdatedPoolIndexes(
                _poolTokenAddress
            );

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor
            );

            return
                InterestRatesModel.computeP2PBorrowIndex(
                    InterestRatesModel.P2PIndexComputeParams({
                        poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                        p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                        lastPoolIndex: lastPoolIndexes.lastBorrowPoolIndex,
                        lastP2PIndex: morpho.p2pBorrowIndex(_poolTokenAddress),
                        p2pDelta: delta.p2pBorrowDelta,
                        p2pAmount: delta.p2pBorrowAmount,
                        reserveFactor: marketParams.reserveFactor
                    })
                );
        }
    }

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolTokenAddress The address of the market.
    /// @param _computeUpdatedIndexes Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return newP2PSupplyIndex The updated peer-to-peer supply index.
    /// @return newP2PBorrowIndex The updated peer-to-peer borrow index.
    /// @return newPoolSupplyIndex The updated pool supply index.
    /// @return newPoolBorrowIndex The updated pool borrow index.
    function getIndexes(address _poolTokenAddress, bool _computeUpdatedIndexes)
        public
        view
        returns (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        )
    {
        if (!_computeUpdatedIndexes) {
            ICToken cToken = ICToken(_poolTokenAddress);

            newPoolSupplyIndex = cToken.exchangeRateStored();
            newPoolBorrowIndex = cToken.borrowIndex();
        } else {
            (newPoolSupplyIndex, newPoolBorrowIndex) = _computeUpdatedPoolIndexes(
                _poolTokenAddress
            );
        }

        Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(_poolTokenAddress);
        if (!_computeUpdatedIndexes || block.number == lastPoolIndexes.lastUpdateBlockNumber) {
            newP2PSupplyIndex = morpho.p2pSupplyIndex(_poolTokenAddress);
            newP2PBorrowIndex = morpho.p2pBorrowIndex(_poolTokenAddress);
        } else {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor
            );

            newP2PSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
                InterestRatesModel.P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                    p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                    lastPoolIndex: lastPoolIndexes.lastSupplyPoolIndex,
                    lastP2PIndex: morpho.p2pSupplyIndex(_poolTokenAddress),
                    p2pDelta: delta.p2pSupplyDelta,
                    p2pAmount: delta.p2pSupplyAmount,
                    reserveFactor: marketParams.reserveFactor
                })
            );
            newP2PBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
                InterestRatesModel.P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                    p2pGrowthFactor: growthFactors.p2pGrowthFactor,
                    lastPoolIndex: lastPoolIndexes.lastBorrowPoolIndex,
                    lastP2PIndex: morpho.p2pBorrowIndex(_poolTokenAddress),
                    p2pDelta: delta.p2pBorrowDelta,
                    p2pAmount: delta.p2pBorrowAmount,
                    reserveFactor: marketParams.reserveFactor
                })
            );
        }
    }

    /// INTERNAL ///

    /// @dev Returns Compound's indexes, optionally computing their virtually updated values.
    /// @param _poolTokenAddress The address of the market.
    /// @return newPoolSupplyIndex The supply index.
    /// @return newPoolBorrowIndex The borrow index.
    function _computeUpdatedPoolIndexes(address _poolTokenAddress)
        internal
        view
        returns (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex)
    {
        ICToken cToken = ICToken(_poolTokenAddress);

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

        // Calculate the interest accumulated into borrows and reserves and the new index.
        uint256 simpleInterestFactor = borrowRateMantissa * blockDelta;
        uint256 interestAccumulated = simpleInterestFactor.mul(borrowsPrior);
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 totalReservesNew = cToken.reserveFactorMantissa().mul(interestAccumulated) +
            reservesPrior;

        newPoolSupplyIndex = totalSupply > 0
            ? (cashPrior + totalBorrowsNew - totalReservesNew).div(totalSupply)
            : cToken.initialExchangeRateMantissa();
        newPoolBorrowIndex = simpleInterestFactor.mul(borrowIndexPrior) + borrowIndexPrior;
    }
}
