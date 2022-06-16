// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../libraries/CompoundMath.sol";

import "./MarketsLens.sol";

/// @title IndexesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol market indexes & rates.
abstract contract IndexesLens is MarketsLens {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct GrowthFactors {
        uint256 poolSupplyGrowthFactor; // The pool's supply index growth factor (in wad).
        uint256 poolBorrowGrowthFactor; // The pool's borrow index growth factor (in wad).
        uint256 p2pMedianGrowthFactor; // Morpho peer-to-peer's median index growth factor (in wad).
    }

    struct P2PIndexComputeParams {
        uint256 poolGrowthFactor; // The pool's index growth factor (in wad).
        uint256 p2pMedianGrowthFactor; // Morpho peer-to-peer's median index growth factor (in wad).
        uint112 lastPoolIndex; // The pool's last stored index.
        uint256 lastP2PIndex; // Morpho's last stored peer-to-peer index.
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in cToken).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
        uint16 reserveFactor; // The reserve factor of the given market (in peer-to-peer unit).
    }

    /// PUBLIC ///

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market.
    /// @return newP2PSupplyIndex The updated peer-to-peer supply index.
    function getUpdatedP2PSupplyIndex(address _poolTokenAddress) public view returns (uint256) {
        if (block.number == morpho.lastPoolIndexes(_poolTokenAddress).lastUpdateBlockNumber)
            return morpho.p2pSupplyIndex(_poolTokenAddress);
        else {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
            Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(
                _poolTokenAddress
            );

            (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = _computePoolIndexes(
                _poolTokenAddress
            );

            GrowthFactors memory growthFactors = _computeGrowthFactors(
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor
            );

            return
                _computeP2PSupplyIndex(
                    P2PIndexComputeParams({
                        poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                        p2pMedianGrowthFactor: growthFactors.p2pMedianGrowthFactor,
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
    function getUpdatedP2PBorrowIndex(address _poolTokenAddress) public view returns (uint256) {
        if (block.number == morpho.lastPoolIndexes(_poolTokenAddress).lastUpdateBlockNumber)
            return morpho.p2pBorrowIndex(_poolTokenAddress);
        else {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
            Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(
                _poolTokenAddress
            );

            (uint256 newPoolSupplyIndex, uint256 newPoolBorrowIndex) = _computePoolIndexes(
                _poolTokenAddress
            );

            GrowthFactors memory growthFactors = _computeGrowthFactors(
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor
            );

            return
                _computeP2PBorrowIndex(
                    P2PIndexComputeParams({
                        poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                        p2pMedianGrowthFactor: growthFactors.p2pMedianGrowthFactor,
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
            (newPoolSupplyIndex, newPoolBorrowIndex) = _computePoolIndexes(_poolTokenAddress);
        }

        if (
            !_computeUpdatedIndexes ||
            block.number == morpho.lastPoolIndexes(_poolTokenAddress).lastUpdateBlockNumber
        ) {
            newP2PSupplyIndex = morpho.p2pSupplyIndex(_poolTokenAddress);
            newP2PBorrowIndex = morpho.p2pBorrowIndex(_poolTokenAddress);
        } else {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
            Types.LastPoolIndexes memory lastPoolIndexes = morpho.lastPoolIndexes(
                _poolTokenAddress
            );

            GrowthFactors memory growthFactors = _computeGrowthFactors(
                newPoolSupplyIndex,
                newPoolBorrowIndex,
                lastPoolIndexes,
                marketParams.p2pIndexCursor
            );

            newP2PSupplyIndex = _computeP2PSupplyIndex(
                P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                    p2pMedianGrowthFactor: growthFactors.p2pMedianGrowthFactor,
                    lastPoolIndex: lastPoolIndexes.lastSupplyPoolIndex,
                    lastP2PIndex: morpho.p2pSupplyIndex(_poolTokenAddress),
                    p2pDelta: delta.p2pSupplyDelta,
                    p2pAmount: delta.p2pSupplyAmount,
                    reserveFactor: marketParams.reserveFactor
                })
            );
            newP2PBorrowIndex = _computeP2PBorrowIndex(
                P2PIndexComputeParams({
                    poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                    p2pMedianGrowthFactor: growthFactors.p2pMedianGrowthFactor,
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
    /// @return newPoolSupplyIndex_ The supply index.
    /// @return newPoolBorrowIndex_ The borrow index.
    function _computePoolIndexes(address _poolTokenAddress)
        internal
        view
        returns (uint256 newPoolSupplyIndex_, uint256 newPoolBorrowIndex_)
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

        newPoolSupplyIndex_ = totalSupply > 0
            ? (cashPrior + totalBorrowsNew - totalReservesNew).div(totalSupply)
            : cToken.initialExchangeRateMantissa();
        newPoolBorrowIndex_ = simpleInterestFactor.mul(borrowIndexPrior) + borrowIndexPrior;
    }

    /// @notice Computes and returns the new growth factors associated to a given pool's supply/borrow index & Morpho's peer-to-peer index.
    /// @param _newPoolSupplyIndex The pool's last current supply index.
    /// @param _newPoolBorrowIndex The pool's last current borrow index.
    /// @param _lastPoolIndexes The pool's last stored indexes.
    /// @param _p2pIndexCursor The peer-to-peer index cursor for the given market.
    /// @return growthFactors_ The pool's indexes growth factor (in wad).
    function _computeGrowthFactors(
        uint256 _newPoolSupplyIndex,
        uint256 _newPoolBorrowIndex,
        Types.LastPoolIndexes memory _lastPoolIndexes,
        uint16 _p2pIndexCursor
    ) internal pure returns (GrowthFactors memory growthFactors_) {
        growthFactors_.poolSupplyGrowthFactor = _newPoolSupplyIndex.div(
            _lastPoolIndexes.lastSupplyPoolIndex
        );
        growthFactors_.poolBorrowGrowthFactor = _newPoolBorrowIndex.div(
            _lastPoolIndexes.lastBorrowPoolIndex
        );
        growthFactors_.p2pMedianGrowthFactor =
            ((MAX_BASIS_POINTS - _p2pIndexCursor) *
                growthFactors_.poolSupplyGrowthFactor +
                _p2pIndexCursor *
                growthFactors_.poolBorrowGrowthFactor) /
            MAX_BASIS_POINTS;
    }

    /// @notice Computes and returns the new peer-to-peer supply index of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return newP2PSupplyIndex_ The updated peer-to-peer index.
    function _computeP2PSupplyIndex(P2PIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex_)
    {
        uint256 p2pGrowthFactor = _params.p2pMedianGrowthFactor -
            (_params.reserveFactor * (_params.p2pMedianGrowthFactor - _params.poolGrowthFactor)) /
            MAX_BASIS_POINTS;

        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PSupplyIndex_ = _params.lastP2PIndex.mul(p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pDelta.mul(_params.lastPoolIndex)).div(
                    (_params.p2pAmount).mul(_params.lastP2PIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PSupplyIndex_ = _params.lastP2PIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pGrowthFactor) +
                    shareOfTheDelta.mul(_params.poolGrowthFactor)
            );
        }
    }

    /// @notice Computes and returns the new peer-to-peer borrow index of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return newP2PBorrowIndex_ The updated peer-to-peer index.
    function _computeP2PBorrowIndex(P2PIndexComputeParams memory _params)
        internal
        pure
        returns (uint256 newP2PBorrowIndex_)
    {
        uint256 p2pGrowthFactor = _params.p2pMedianGrowthFactor +
            (_params.reserveFactor * (_params.poolGrowthFactor - _params.p2pMedianGrowthFactor)) /
            MAX_BASIS_POINTS;

        if (_params.p2pAmount == 0 || _params.p2pDelta == 0) {
            newP2PBorrowIndex_ = _params.lastP2PIndex.mul(p2pGrowthFactor);
        } else {
            uint256 shareOfTheDelta = CompoundMath.min(
                (_params.p2pDelta.mul(_params.lastPoolIndex)).div(
                    (_params.p2pAmount).mul(_params.lastP2PIndex)
                ),
                WAD // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newP2PBorrowIndex_ = _params.lastP2PIndex.mul(
                (WAD - shareOfTheDelta).mul(p2pGrowthFactor) +
                    shareOfTheDelta.mul(_params.poolGrowthFactor)
            );
        }
    }
}
