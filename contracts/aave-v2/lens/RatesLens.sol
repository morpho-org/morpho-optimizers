// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/aave/IVariableDebtToken.sol";

import "./UsersLens.sol";

/// @title RatesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract RatesLens is UsersLens {
    using WadRayMath for uint256;

    /// STRUCTS ///

    struct Indexes {
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
    }

    /// EXTERNAL ///

    /// @notice Returns the supply rate per year experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned supply rate is a lower bound: when supplying through Morpho-Compound,
    /// a supplier could be matched more than once instantly or later and thus benefit from a higher supply rate.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The address of the user on behalf of whom to supply.
    /// @param _amount The amount to supply.
    /// @return nextSupplyRatePerYear An approximation of the next supply rate per year experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserSupplyRatePerYear(
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
        (
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex,
            indexes.poolBorrowIndex
        ) = _getCurrentP2PSupplyIndex(_poolTokenAddress);

        if (_amount > 0) {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            if (delta.p2pBorrowDelta > 0) {
                uint256 deltaInUnderlying = delta.p2pBorrowDelta.rayMul(indexes.poolBorrowIndex);
                uint256 matchedDelta = Math.min(deltaInUnderlying, _amount);

                supplyBalance.inP2P += matchedDelta.rayDiv(indexes.p2pSupplyIndex);
                _amount -= matchedDelta;
            }
        }

        if (_amount > 0 && !morpho.p2pDisabled(_poolTokenAddress)) {
            uint256 firstPoolBorrowerBalance = morpho
            .borrowBalanceInOf(
                _poolTokenAddress,
                morpho.getHead(_poolTokenAddress, Types.PositionType.BORROWERS_ON_POOL)
            ).onPool;

            if (firstPoolBorrowerBalance > 0) {
                uint256 borrowerBalanceInUnderlying = firstPoolBorrowerBalance.rayMul(
                    indexes.poolBorrowIndex
                );
                uint256 matchedP2P = Math.min(borrowerBalanceInUnderlying, _amount);

                supplyBalance.inP2P += matchedP2P.rayDiv(indexes.p2pSupplyIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) supplyBalance.onPool += _amount.rayDiv(indexes.poolSupplyIndex);

        balanceOnPool = supplyBalance.onPool.rayMul(indexes.poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.rayMul(indexes.p2pSupplyIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextSupplyRatePerYear = _getUserSupplyRatePerYear(
            _poolTokenAddress,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// @notice Returns the borrow rate per year experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned borrow rate is an upper bound: when borrowing through Morpho-Aave,
    /// a borrower could be matched more than once instantly or later and thus benefit from a lower borrow rate.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The address of the user on behalf of whom to borrow.
    /// @param _amount The amount to borrow.
    /// @return nextBorrowRatePerYear An approximation of the next borrow rate per year experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserBorrowRatePerYear(
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
        (
            indexes.p2pBorrowIndex,
            indexes.poolSupplyIndex,
            indexes.poolBorrowIndex
        ) = _getCurrentP2PBorrowIndex(_poolTokenAddress);

        if (_amount > 0) {
            Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
            if (delta.p2pSupplyDelta > 0) {
                uint256 deltaInUnderlying = delta.p2pSupplyDelta.rayMul(indexes.poolSupplyIndex);
                uint256 matchedDelta = Math.min(deltaInUnderlying, _amount);

                borrowBalance.inP2P += matchedDelta.rayDiv(indexes.p2pBorrowIndex);
                _amount -= matchedDelta;
            }
        }

        if (_amount > 0 && !morpho.p2pDisabled(_poolTokenAddress)) {
            uint256 firstPoolSupplierBalance = morpho
            .supplyBalanceInOf(
                _poolTokenAddress,
                morpho.getHead(_poolTokenAddress, Types.PositionType.SUPPLIERS_ON_POOL)
            ).onPool;

            if (firstPoolSupplierBalance > 0) {
                uint256 supplierBalanceInUnderlying = firstPoolSupplierBalance.rayMul(
                    indexes.poolSupplyIndex
                );
                uint256 matchedP2P = Math.min(supplierBalanceInUnderlying, _amount);

                borrowBalance.inP2P += matchedP2P.rayDiv(indexes.p2pBorrowIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) borrowBalance.onPool += _amount.rayDiv(indexes.poolBorrowIndex);

        balanceOnPool = borrowBalance.onPool.rayMul(indexes.poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.rayMul(indexes.p2pBorrowIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextBorrowRatePerYear = _getUserBorrowRatePerYear(
            _poolTokenAddress,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// PUBLIC ///

    /// @notice Computes and returns the current supply rate per year experienced on average on a given market.
    /// @param _poolTokenAddress The market address.
    /// @return avgSupplyRatePerYear The market's average supply rate per year (in wad).
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function getAverageSupplyRatePerYear(address _poolTokenAddress)
        public
        view
        returns (
            uint256 avgSupplyRatePerYear,
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount
        )
    {
        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 poolSupplyRate = reserve.currentLiquidityRate;
        uint256 poolBorrowRate = reserve.currentVariableBorrowRate;

        (uint256 p2pSupplyIndex, uint256 poolSupplyIndex, ) = _getCurrentP2PSupplyIndex(
            _poolTokenAddress
        );

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
        // do not take delta into account as it's already taken into account in p2pSupplyAmount & poolSupplyAmount
        uint256 p2pSupplyRate = InterestRatesModel.computeP2PSupplyRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: InterestRatesModel.percentAvg(
                    poolSupplyRate,
                    poolBorrowRate,
                    marketParams.p2pIndexCursor
                ),
                poolRate: poolSupplyRate,
                poolIndex: poolSupplyIndex,
                p2pIndex: p2pSupplyIndex,
                p2pDelta: 0,
                p2pAmount: 0,
                reserveFactor: marketParams.reserveFactor
            })
        );

        (p2pSupplyAmount, poolSupplyAmount) = _getMarketSupply(
            _poolTokenAddress,
            p2pSupplyIndex,
            poolSupplyIndex
        );

        uint256 totalSupply = p2pSupplyAmount + poolSupplyAmount;
        if (p2pSupplyAmount > 0)
            avgSupplyRatePerYear += p2pSupplyRate.wadMul(p2pSupplyAmount.wadDiv(totalSupply));
        if (poolSupplyAmount > 0)
            avgSupplyRatePerYear += poolSupplyRate.wadMul(poolSupplyAmount.wadDiv(totalSupply));
    }

    /// @notice Computes and returns the current average borrow rate per year experienced on a given market.
    /// @param _poolTokenAddress The market address.
    /// @return avgBorrowRatePerYear The market's average borrow rate per year (in wad).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getAverageBorrowRatePerYear(address _poolTokenAddress)
        public
        view
        returns (
            uint256 avgBorrowRatePerYear,
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount
        )
    {
        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 poolSupplyRate = reserve.currentLiquidityRate;
        uint256 poolBorrowRate = reserve.currentVariableBorrowRate;

        (uint256 p2pBorrowIndex, , uint256 poolBorrowIndex) = _getCurrentP2PBorrowIndex(
            _poolTokenAddress
        );

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
        // do not take delta into account as it's already taken into account in p2pBorrowAmount & poolBorrowAmount
        uint256 p2pBorrowRate = InterestRatesModel.computeP2PBorrowRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: InterestRatesModel.percentAvg(
                    poolSupplyRate,
                    poolBorrowRate,
                    marketParams.p2pIndexCursor
                ),
                poolRate: poolBorrowRate,
                poolIndex: poolBorrowIndex,
                p2pIndex: p2pBorrowIndex,
                p2pDelta: 0,
                p2pAmount: 0,
                reserveFactor: marketParams.reserveFactor
            })
        );

        (p2pBorrowAmount, poolBorrowAmount) = _getMarketBorrow(
            reserve,
            p2pBorrowIndex,
            poolBorrowIndex
        );

        uint256 totalBorrow = p2pBorrowAmount + poolBorrowAmount;
        if (p2pBorrowAmount > 0)
            avgBorrowRatePerYear += p2pBorrowRate.wadMul(p2pBorrowAmount.wadDiv(totalBorrow));
        if (poolBorrowAmount > 0)
            avgBorrowRatePerYear += poolBorrowRate.wadMul(poolBorrowAmount.wadDiv(totalBorrow));
    }

    /// @notice Computes and returns peer-to-peer and pool rates for a specific market.
    /// @dev Note: prefer using getAverageSupplyRatePerBlock & getAverageBorrowRatePerBlock to get the experienced supply/borrow rate instead of this.
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate The market's peer-to-peer supply rate per year (in wad).
    /// @return p2pBorrowRate The market's peer-to-peer borrow rate per year (in wad).
    /// @return poolSupplyRate The market's pool supply rate per year (in wad).
    /// @return poolBorrowRate The market's pool borrow rate per year (in wad).
    function getRatesPerYear(address _poolTokenAddress)
        public
        view
        returns (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        )
    {
        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
        );

        poolSupplyRate = reserve.currentLiquidityRate;
        poolBorrowRate = reserve.currentVariableBorrowRate;

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolTokenAddress);
        uint256 p2pRate = InterestRatesModel.percentAvg(
            poolSupplyRate,
            poolBorrowRate,
            marketParams.p2pIndexCursor
        );

        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = getIndexes(_poolTokenAddress);

        p2pSupplyRate = InterestRatesModel.computeP2PSupplyRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolSupplyRate,
                poolIndex: poolSupplyIndex,
                p2pIndex: p2pSupplyIndex,
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount,
                reserveFactor: marketParams.reserveFactor
            })
        );

        p2pBorrowRate = InterestRatesModel.computeP2PBorrowRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolBorrowRate,
                poolIndex: poolBorrowIndex,
                p2pIndex: p2pBorrowIndex,
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount,
                reserveFactor: marketParams.reserveFactor
            })
        );
    }

    /// @notice Returns the supply rate per year a given user is currently experiencing on a given market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to compute the supply rate per year for.
    /// @return The supply rate per year the user is currently experiencing (in wad).
    function getCurrentUserSupplyRatePerYear(address _poolTokenAddress, address _user)
        public
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getCurrentSupplyBalanceInOf(_poolTokenAddress, _user);

        return
            _getUserSupplyRatePerYear(_poolTokenAddress, balanceOnPool, balanceInP2P, totalBalance);
    }

    /// @notice Returns the borrow rate per year a given user is currently experiencing on a given market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to compute the borrow rate per year for.
    /// @return The borrow rate per year the user is currently experiencing (in wad).
    function getCurrentUserBorrowRatePerYear(address _poolTokenAddress, address _user)
        public
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getCurrentBorrowBalanceInOf(_poolTokenAddress, _user);

        return
            _getUserBorrowRatePerYear(_poolTokenAddress, balanceOnPool, balanceInP2P, totalBalance);
    }

    /// INTERNAL ///

    /// @notice Computes and returns the total distribution of supply for a given market, optionally using virtually updated indexes.
    /// @param _poolTokenAddress The address of the market to check.
    /// @param _p2pSupplyIndex The given market's peer-to-peer supply index.
    /// @param _poolSupplyIndex The underlying pool's supply index.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function _getMarketSupply(
        address _poolTokenAddress,
        uint256 _p2pSupplyIndex,
        uint256 _poolSupplyIndex
    ) internal view returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount) {
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);

        p2pSupplyAmount =
            delta.p2pSupplyAmount.rayMul(_p2pSupplyIndex) -
            delta.p2pSupplyDelta.rayMul(_poolSupplyIndex);
        poolSupplyAmount = IAToken(_poolTokenAddress).balanceOf(address(morpho)).rayMul(
            _poolSupplyIndex
        );
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, optionally using virtually updated indexes.
    /// @param reserve The reserve data of the underlying pool.
    /// @param _p2pBorrowIndex The given market's peer-to-peer borrow index.
    /// @param _poolBorrowIndex The underlying pool's borrow index.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function _getMarketBorrow(
        DataTypes.ReserveData memory reserve,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex
    ) internal view returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) {
        Types.Delta memory delta = morpho.deltas(reserve.aTokenAddress);

        p2pBorrowAmount =
            delta.p2pBorrowAmount.rayMul(_p2pBorrowIndex) -
            delta.p2pBorrowDelta.rayMul(_poolBorrowIndex);
        poolBorrowAmount = IVariableDebtToken(reserve.variableDebtTokenAddress).scaledBalanceOf(
            address(morpho)
        );
    }

    /// @dev Returns the supply rate per year experienced on a market based on a given position distribution.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P` and `_totalBalance`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool` and `_totalBalance`).
    /// @param _totalBalance The total amount of balance (should equal `_balanceOnPool + _balanceInP2P` but is used for saving gas).
    /// @return supplyRatePerYear The supply rate per year experienced by the given position (in wad).
    function _getUserSupplyRatePerYear(
        address _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256 supplyRatePerYear) {
        if (_totalBalance == 0) return 0;

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = getRatesPerYear(_poolTokenAddress);

        if (_balanceOnPool > 0)
            supplyRatePerYear += poolSupplyRate.wadMul(_balanceOnPool.wadDiv(_totalBalance));
        if (_balanceInP2P > 0)
            supplyRatePerYear += p2pSupplyRate.wadMul(_balanceInP2P.wadDiv(_totalBalance));
    }

    /// @dev Returns the borrow rate per year experienced on a market based on a given position distribution.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P` and `_totalBalance`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool` and `_totalBalance`).
    /// @param _totalBalance The total amount of balance (should equal `_balanceOnPool + _balanceInP2P` but is used for saving gas).
    /// @return borrowRatePerYear The borrow rate per year experienced by the given position (in wad).
    function _getUserBorrowRatePerYear(
        address _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256 borrowRatePerYear) {
        if (_totalBalance == 0) return 0;

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = getRatesPerYear(_poolTokenAddress);

        if (_balanceOnPool > 0)
            borrowRatePerYear += poolBorrowRate.wadMul(_balanceOnPool.wadDiv(_totalBalance));
        if (_balanceInP2P > 0)
            borrowRatePerYear += p2pBorrowRate.wadMul(_balanceInP2P.wadDiv(_totalBalance));
    }
}
