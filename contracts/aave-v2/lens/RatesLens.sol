// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../libraries/InterestRatesModel.sol";

import "./UsersLens.sol";

/// @title RatesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract RatesLens is UsersLens {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    /// STRUCTS ///

    struct Indexes {
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
    }

    /// EXTERNAL ///

    /// @notice Returns the supply rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev The returned supply rate is only an approximation: it only takes into accounts current delta and the head of the data structure.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The address of the user on behalf of whom to supply.
    /// @param _amount The amount to supply.
    /// @return nextSupplyRatePerYear An approximation of the next supply rate per block experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextSupplyRatePerYear(
        address _poolTokenAddress,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextSupplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(
            _poolTokenAddress,
            _user
        );

        Indexes memory indexes;
        (indexes.p2pSupplyIndex, , indexes.poolSupplyIndex, indexes.poolBorrowIndex) = getIndexes(
            _poolTokenAddress,
            true
        );

        if (_amount > 0) {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            if (delta.p2pBorrowDelta > 0) {
                uint256 deltaInUnderlying = delta.p2pBorrowDelta.mul(indexes.poolBorrowIndex);
                uint256 matchedDelta = Math.min(deltaInUnderlying, _amount);

                supplyBalance.inP2P += matchedDelta.div(indexes.p2pSupplyIndex);
                _amount -= matchedDelta;
            }
        }

        if (_amount > 0) {
            uint256 firstPoolBorrowerBalance = morpho
            .borrowBalanceInOf(
                _poolTokenAddress,
                morpho.getHead(_poolTokenAddress, Types.PositionType.BORROWERS_ON_POOL)
            ).onPool;

            if (firstPoolBorrowerBalance > 0) {
                uint256 borrowerBalanceInUnderlying = firstPoolBorrowerBalance.mul(
                    indexes.poolBorrowIndex
                );
                uint256 matchedP2P = Math.min(borrowerBalanceInUnderlying, _amount);

                supplyBalance.inP2P += matchedP2P.div(indexes.p2pSupplyIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) supplyBalance.onPool += _amount.div(indexes.poolSupplyIndex);

        balanceOnPool = supplyBalance.onPool.mul(indexes.poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.mul(indexes.p2pSupplyIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextSupplyRatePerYear = _computeUserSupplyRatePerYear(
            _poolTokenAddress,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// @notice Returns the borrow rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev The returned borrow rate is only an approximation: it only takes into accounts current delta and the head of the data structure.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The address of the user on behalf of whom to borrow.
    /// @param _amount The amount to borrow.
    /// @return nextBorrowRatePerYear An approximation of the next borrow rate per block experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextBorrowRatePerYear(
        address _poolTokenAddress,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextBorrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(
            _poolTokenAddress,
            _user
        );

        Indexes memory indexes;
        (, indexes.p2pBorrowIndex, indexes.poolSupplyIndex, indexes.poolBorrowIndex) = getIndexes(
            _poolTokenAddress,
            true
        );

        if (_amount > 0) {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            if (delta.p2pSupplyDelta > 0) {
                uint256 deltaInUnderlying = delta.p2pSupplyDelta.mul(indexes.poolSupplyIndex);
                uint256 matchedDelta = Math.min(deltaInUnderlying, _amount);

                borrowBalance.inP2P += matchedDelta.div(indexes.p2pBorrowIndex);
                _amount -= matchedDelta;
            }
        }

        if (_amount > 0) {
            uint256 firstPoolSupplierBalance = morpho
            .supplyBalanceInOf(
                _poolTokenAddress,
                morpho.getHead(_poolTokenAddress, Types.PositionType.SUPPLIERS_ON_POOL)
            ).onPool;

            if (firstPoolSupplierBalance > 0) {
                uint256 supplierBalanceInUnderlying = firstPoolSupplierBalance.mul(
                    indexes.poolSupplyIndex
                );
                uint256 matchedP2P = Math.min(supplierBalanceInUnderlying, _amount);

                borrowBalance.inP2P += matchedP2P.div(indexes.p2pBorrowIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) borrowBalance.onPool += _amount.div(indexes.poolBorrowIndex);

        balanceOnPool = borrowBalance.onPool.mul(indexes.poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.mul(indexes.p2pBorrowIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextBorrowRatePerYear = _computeUserBorrowRatePerYear(
            _poolTokenAddress,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// PUBLIC ///

    /// @notice Computes and returns peer-to-peer and pool rates for a specific market.
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate_ The market's peer-to-peer supply rate per block (in wad).
    /// @return p2pBorrowRate_ The market's peer-to-peer borrow rate per block (in wad).
    /// @return poolSupplyRate_ The market's pool supply rate per block (in wad).
    /// @return poolBorrowRate_ The market's pool borrow rate per block (in wad).
    function getRatesPerYear(address _poolTokenAddress)
        public
        view
        returns (
            uint256 p2pSupplyRate_,
            uint256 p2pBorrowRate_,
            uint256 poolSupplyRate_,
            uint256 poolBorrowRate_
        )
    {
        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
        );

        poolSupplyRate_ = reserve.currentLiquidityRate;
        poolBorrowRate_ = reserve.currentVariableBorrowRate;
        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);

        uint256 p2pRate = ((MAX_BASIS_POINTS - marketParams.p2pIndexCursor) *
            poolSupplyRate_ +
            marketParams.p2pIndexCursor *
            poolBorrowRate_) / MAX_BASIS_POINTS;

        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        ) = getIndexes(_poolTokenAddress, true);

        p2pSupplyRate_ = InterestRatesModel.computeP2PSupplyRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolSupplyRate_,
                poolIndex: newPoolSupplyIndex,
                p2pIndex: newP2PSupplyIndex,
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount,
                reserveFactor: marketParams.reserveFactor
            })
        );

        p2pBorrowRate_ = InterestRatesModel.computeP2PBorrowRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolBorrowRate_,
                poolIndex: newPoolBorrowIndex,
                p2pIndex: newP2PBorrowIndex,
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount,
                reserveFactor: marketParams.reserveFactor
            })
        );
    }

    /// @notice Returns the supply rate per block a given user is currently experiencing on a given market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to compute the supply rate per block for.
    /// @return The supply rate per block the user is currently experiencing (in wad).
    function getUpdatedUserSupplyRatePerYear(address _poolTokenAddress, address _user)
        public
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getUpdatedUserSupplyBalance(_user, _poolTokenAddress);

        return
            _computeUserSupplyRatePerYear(
                _poolTokenAddress,
                balanceOnPool,
                balanceInP2P,
                totalBalance
            );
    }

    /// @notice Returns the borrow rate per block a given user is currently experiencing on a given market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to compute the borrow rate per block for.
    /// @return The borrow rate per block the user is currently experiencing (in wad).
    function getUpdatedUserBorrowRatePerYear(address _poolTokenAddress, address _user)
        public
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getUpdatedUserBorrowBalance(_user, _poolTokenAddress);

        return
            _computeUserBorrowRatePerYear(
                _poolTokenAddress,
                balanceOnPool,
                balanceInP2P,
                totalBalance
            );
    }

    /// INTERNAL ///

    /// @dev Returns the supply rate per block experienced on a market based on a given position distribution.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P` and `_totalBalance`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool` and `_totalBalance`).
    /// @param _totalBalance The total amount of balance (should equal `_balanceOnPool + _balanceInP2P` but is used for saving gas).
    /// @return The supply rate per block experienced by the given position (in wad).
    function _computeUserSupplyRatePerYear(
        address _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256) {
        if (_totalBalance == 0) return 0;

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = getRatesPerYear(_poolTokenAddress);

        return
            (poolSupplyRate.mul(_balanceOnPool) + p2pSupplyRate.mul(_balanceInP2P)).div(
                _totalBalance
            );
    }

    /// @dev Returns the borrow rate per block experienced on a market based on a given position distribution.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P` and `_totalBalance`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool` and `_totalBalance`).
    /// @param _totalBalance The total amount of balance (should equal `_balanceOnPool + _balanceInP2P` but is used for saving gas).
    /// @return The borrow rate per block experienced by the given position (in wad).
    function _computeUserBorrowRatePerYear(
        address _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256) {
        if (_totalBalance == 0) return 0;

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = getRatesPerYear(_poolTokenAddress);

        return
            (poolBorrowRate.mul(_balanceOnPool) + p2pBorrowRate.mul(_balanceInP2P)).div(
                _totalBalance
            );
    }
}
