// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IInterestRatesManager.sol";

import "./libraries/InterestRatesModel.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";

import "./MorphoStorage.sol";

/// @title InterestRatesManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract handling the computation of indexes used for peer-to-peer interactions.
/// @dev This contract inherits from MorphoStorage so that Morpho can delegate calls to this contract.
contract InterestRatesManager is IInterestRatesManager, MorphoStorage {
    using CompoundMath for uint256;
    using PercentageMath for uint256;

    /// STRUCTS ///

    struct Params {
        uint256 lastP2PSupplyIndex; // The peer-to-peer supply index at last update.
        uint256 lastP2PBorrowIndex; // The peer-to-peer borrow index at last update.
        uint256 poolSupplyIndex; // The current pool supply index.
        uint256 poolBorrowIndex; // The current pool borrow index.
        Types.LastPoolIndexes lastPoolIndexes; // The pool indexes at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Types.Delta delta; // The deltas and peer-to-peer amounts.
    }

    /// EVENTS ///

    /// @notice Emitted when the peer-to-peer indexes of a market are updated.
    /// @param _poolToken The address of the market updated.
    /// @param _p2pSupplyIndex The updated supply index from peer-to-peer unit to underlying.
    /// @param _p2pBorrowIndex The updated borrow index from peer-to-peer unit to underlying.
    /// @param _poolSupplyIndex The updated pool supply index.
    /// @param _poolBorrowIndex The updated pool borrow index.
    event P2PIndexesUpdated(
        address indexed _poolToken,
        uint256 _p2pSupplyIndex,
        uint256 _p2pBorrowIndex,
        uint256 _poolSupplyIndex,
        uint256 _poolBorrowIndex
    );

    /// EXTERNAL ///

    /// @notice Updates the peer-to-peer indexes.
    /// @param _poolToken The address of the market to update.
    function updateP2PIndexes(address _poolToken) external {
        Types.LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolToken];

        if (block.number <= poolIndexes.lastUpdateBlockNumber) return;

        Types.MarketParameters memory marketParams = marketParameters[_poolToken];

        uint256 poolSupplyIndex = ICToken(_poolToken).exchangeRateCurrent();
        uint256 poolBorrowIndex = ICToken(_poolToken).borrowIndex();

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(
            Params({
                lastP2PSupplyIndex: p2pSupplyIndex[_poolToken],
                lastP2PBorrowIndex: p2pBorrowIndex[_poolToken],
                poolSupplyIndex: poolSupplyIndex,
                poolBorrowIndex: poolBorrowIndex,
                lastPoolIndexes: poolIndexes,
                reserveFactor: marketParams.reserveFactor,
                p2pIndexCursor: marketParams.p2pIndexCursor,
                delta: deltas[_poolToken]
            })
        );

        p2pSupplyIndex[_poolToken] = newP2PSupplyIndex;
        p2pBorrowIndex[_poolToken] = newP2PBorrowIndex;

        poolIndexes.lastUpdateBlockNumber = uint32(block.number);
        poolIndexes.lastSupplyPoolIndex = uint112(poolSupplyIndex);
        poolIndexes.lastBorrowPoolIndex = uint112(poolBorrowIndex);

        emit P2PIndexesUpdated(
            _poolToken,
            newP2PSupplyIndex,
            newP2PBorrowIndex,
            poolSupplyIndex,
            poolBorrowIndex
        );
    }

    /// PUBLIC ///

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

    /// @notice Returns the updated peer-to-peer and pool indexes.
    /// @param _poolToken The address of the market.
    /// @param _updated Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @return indexes The given market's updated indexes.
    /// @return delta The given market's deltas.
    function getIndexes(address _poolToken, bool _updated)
        public
        view
        returns (Types.Indexes memory indexes, Types.Delta memory delta)
    {
        if (!_updated) {
            ICToken cToken = ICToken(_poolToken);

            indexes.poolSupplyIndex = cToken.exchangeRateStored();
            indexes.poolBorrowIndex = cToken.borrowIndex();
        } else {
            (indexes.poolSupplyIndex, indexes.poolBorrowIndex) = getCurrentPoolIndexes(_poolToken);
        }

        delta = deltas[_poolToken];
        Types.LastPoolIndexes memory poolIndexes = lastPoolIndexes[_poolToken];

        if (!_updated || block.number == poolIndexes.lastUpdateBlockNumber) {
            indexes.p2pSupplyIndex = p2pSupplyIndex[_poolToken];
            indexes.p2pBorrowIndex = p2pBorrowIndex[_poolToken];
        } else {
            Types.MarketParameters memory marketParams = marketParameters[_poolToken];

            (indexes.p2pSupplyIndex, indexes.p2pBorrowIndex) = _computeP2PIndexes(
                Params({
                    lastP2PSupplyIndex: p2pSupplyIndex[_poolToken],
                    lastP2PBorrowIndex: p2pBorrowIndex[_poolToken],
                    poolSupplyIndex: indexes.poolSupplyIndex,
                    poolBorrowIndex: indexes.poolBorrowIndex,
                    lastPoolIndexes: poolIndexes,
                    reserveFactor: marketParams.reserveFactor,
                    p2pIndexCursor: marketParams.p2pIndexCursor,
                    delta: delta
                })
            );
        }
    }

    /// INTERNAL ///

    /// @notice Computes and returns new peer-to-peer indexes.
    /// @param _params Computation parameters.
    /// @return newP2PSupplyIndex The updated p2pSupplyIndex.
    /// @return newP2PBorrowIndex The updated p2pBorrowIndex.
    function _computeP2PIndexes(Params memory _params)
        internal
        pure
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        InterestRatesModel.GrowthFactors memory growthFactors = InterestRatesModel
        .computeGrowthFactors(
            _params.poolSupplyIndex,
            _params.poolBorrowIndex,
            _params.lastPoolIndexes,
            _params.p2pIndexCursor,
            _params.reserveFactor
        );

        newP2PSupplyIndex = InterestRatesModel.computeP2PIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolSupplyGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pSupplyGrowthFactor,
                lastPoolIndex: _params.lastPoolIndexes.lastSupplyPoolIndex,
                lastP2PIndex: _params.lastP2PSupplyIndex,
                p2pDelta: _params.delta.p2pSupplyDelta,
                p2pAmount: _params.delta.p2pSupplyAmount
            })
        );
        newP2PBorrowIndex = InterestRatesModel.computeP2PIndex(
            InterestRatesModel.P2PIndexComputeParams({
                poolGrowthFactor: growthFactors.poolBorrowGrowthFactor,
                p2pGrowthFactor: growthFactors.p2pBorrowGrowthFactor,
                lastPoolIndex: _params.lastPoolIndexes.lastBorrowPoolIndex,
                lastP2PIndex: _params.lastP2PBorrowIndex,
                p2pDelta: _params.delta.p2pBorrowDelta,
                p2pAmount: _params.delta.p2pBorrowAmount
            })
        );
    }
}
