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

    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @param _updated Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return indexes The given market's virtually updated indexes.
    function getIndexes(address _poolToken, bool _updated)
        public
        view
        returns (Types.Indexes memory indexes)
    {
        (, indexes) = _getIndexes(_poolToken, _updated);
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

        poolSupplyIndex = (cashPrior + totalBorrowsNew - totalReservesNew).div(totalSupply);
        poolBorrowIndex = simpleInterestFactor.mul(borrowIndexPrior) + borrowIndexPrior;
    }

    /// INTERNAL ///

    /// @notice Returns the updated peer-to-peer and pool indexes.
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
            ICToken cToken = ICToken(_poolToken);

            indexes.poolSupplyIndex = cToken.exchangeRateStored();
            indexes.poolBorrowIndex = cToken.borrowIndex();
        } else {
            (indexes.poolSupplyIndex, indexes.poolBorrowIndex) = getCurrentPoolIndexes(_poolToken);
        }

        if (!_updated || block.number == lastPoolIndexes.lastUpdateBlockNumber) {
            indexes.p2pSupplyIndex = morpho.p2pSupplyIndex(_poolToken);
            indexes.p2pBorrowIndex = morpho.p2pBorrowIndex(_poolToken);
        } else {
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);

            InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
            .computeGrowthFactors(
                indexes.poolSupplyIndex,
                indexes.poolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor,
                marketParams.reserveFactor
            );

            indexes.p2pSupplyIndex = InterestRatesModel.computeP2PSupplyIndex(
                InterestRatesModel.P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                    p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                    lastPoolIndex: lastPoolIndexes.lastSupplyPoolIndex,
                    lastP2PIndex: morpho.p2pSupplyIndex(_poolToken),
                    p2pDelta: delta.p2pSupplyDelta,
                    p2pAmount: delta.p2pSupplyAmount
                })
            );
            indexes.p2pBorrowIndex = InterestRatesModel.computeP2PBorrowIndex(
                InterestRatesModel.P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                    p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                    lastPoolIndex: lastPoolIndexes.lastBorrowPoolIndex,
                    lastP2PIndex: morpho.p2pBorrowIndex(_poolToken),
                    p2pDelta: delta.p2pBorrowDelta,
                    p2pAmount: delta.p2pBorrowAmount
                })
            );
        }
    }
}
