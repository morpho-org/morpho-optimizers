// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/aave/IVariableDebtToken.sol";

import "./UsersLens.sol";

/// @title RatesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract RatesLens is UsersLens {
    using WadRayMath for uint256;
    using Math for uint256;

    /// EXTERNAL ///

    /// @notice Returns the supply rate per year experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned supply rate is a low estimate: when supplying through Morpho-Aave,
    /// a supplier could be matched more than once instantly or later and thus benefit from a higher supply rate.
    /// @param _poolToken The address of the market.
    /// @param _user The address of the user on behalf of whom to supply.
    /// @param _amount The amount to supply.
    /// @return nextSupplyRatePerYear An approximation of the next supply rate per year experienced after having supplied (in ray).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserSupplyRatePerYear(
        address _poolToken,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextSupplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        ) = _getIndexes(_poolToken);

        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(_poolToken, _user);
        if (_amount > 0 && delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(indexes.poolBorrowIndex),
                _amount
            );

            supplyBalance.inP2P += matchedDelta.rayDiv(indexes.p2pSupplyIndex);
            _amount -= matchedDelta;
        }

        if (_amount > 0 && !market.isP2PDisabled) {
            address firstPoolBorrower = morpho.getHead(
                _poolToken,
                Types.PositionType.BORROWERS_ON_POOL
            );
            uint256 firstPoolBorrowerBalance = morpho
            .borrowBalanceInOf(_poolToken, firstPoolBorrower)
            .onPool;

            if (firstPoolBorrowerBalance > 0) {
                uint256 matchedP2P = Math.min(
                    firstPoolBorrowerBalance.rayMul(indexes.poolBorrowIndex),
                    _amount
                );

                supplyBalance.inP2P += matchedP2P.rayDiv(indexes.p2pSupplyIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) supplyBalance.onPool += _amount.rayDiv(indexes.poolSupplyIndex);

        balanceOnPool = supplyBalance.onPool.rayMul(indexes.poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.rayMul(indexes.p2pSupplyIndex);

        (nextSupplyRatePerYear, totalBalance) = _getUserSupplyRatePerYear(
            _poolToken,
            balanceInP2P,
            balanceOnPool
        );
    }

    /// @notice Returns the borrow rate per year experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned borrow rate is a high estimate: when borrowing through Morpho-Aave,
    /// a borrower could be matched more than once instantly or later and thus benefit from a lower borrow rate.
    /// @param _poolToken The address of the market.
    /// @param _user The address of the user on behalf of whom to borrow.
    /// @param _amount The amount to borrow.
    /// @return nextBorrowRatePerYear An approximation of the next borrow rate per year experienced after having supplied (in ray).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserBorrowRatePerYear(
        address _poolToken,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextBorrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        ) = _getIndexes(_poolToken);

        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(_poolToken, _user);
        if (_amount > 0 && delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.rayMul(indexes.poolSupplyIndex),
                _amount
            );

            borrowBalance.inP2P += matchedDelta.rayDiv(indexes.p2pBorrowIndex);
            _amount -= matchedDelta;
        }

        if (_amount > 0 && !market.isP2PDisabled) {
            address firstPoolSupplier = morpho.getHead(
                _poolToken,
                Types.PositionType.SUPPLIERS_ON_POOL
            );
            uint256 firstPoolSupplierBalance = morpho
            .supplyBalanceInOf(_poolToken, firstPoolSupplier)
            .onPool;

            if (firstPoolSupplierBalance > 0) {
                uint256 matchedP2P = Math.min(
                    firstPoolSupplierBalance.rayMul(indexes.poolSupplyIndex),
                    _amount
                );

                borrowBalance.inP2P += matchedP2P.rayDiv(indexes.p2pBorrowIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) borrowBalance.onPool += _amount.rayDiv(indexes.poolBorrowIndex);

        balanceOnPool = borrowBalance.onPool.rayMul(indexes.poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.rayMul(indexes.p2pBorrowIndex);

        (nextBorrowRatePerYear, totalBalance) = _getUserBorrowRatePerYear(
            _poolToken,
            balanceInP2P,
            balanceOnPool
        );
    }

    /// @notice Returns the supply rate per year a given user is currently experiencing on a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to compute the supply rate per year for.
    /// @return supplyRatePerYear The supply rate per year the user is currently experiencing (in wad).
    function getCurrentUserSupplyRatePerYear(address _poolToken, address _user)
        external
        view
        returns (uint256 supplyRatePerYear)
    {
        (, uint256 balanceInP2P, uint256 balanceOnPool, ) = _getCurrentSupplyBalanceInOf(
            _poolToken,
            _user
        );

        (supplyRatePerYear, ) = _getUserSupplyRatePerYear(_poolToken, balanceInP2P, balanceOnPool);
    }

    /// @notice Returns the borrow rate per year a given user is currently experiencing on a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to compute the borrow rate per year for.
    /// @return borrowRatePerYear The borrow rate per year the user is currently experiencing (in wad).
    function getCurrentUserBorrowRatePerYear(address _poolToken, address _user)
        external
        view
        returns (uint256 borrowRatePerYear)
    {
        (, uint256 balanceInP2P, uint256 balanceOnPool, ) = _getCurrentBorrowBalanceInOf(
            _poolToken,
            _user
        );

        (borrowRatePerYear, ) = _getUserBorrowRatePerYear(_poolToken, balanceInP2P, balanceOnPool);
    }

    /// PUBLIC ///

    /// @notice Computes and returns the current supply rate per year experienced on average on a given market.
    /// @param _poolToken The market address.
    /// @return avgSupplyRatePerYear The market's average supply rate per year (in ray).
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function getAverageSupplyRatePerYear(address _poolToken)
        public
        view
        returns (
            uint256 avgSupplyRatePerYear,
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount
        )
    {
        (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        ) = _getIndexes(_poolToken);

        DataTypes.ReserveData memory reserve = pool.getReserveData(market.underlyingToken);
        uint256 poolSupplyRatePerYear = reserve.currentLiquidityRate;

        // Do not take delta into account as it's already taken into account in p2pSupplyAmount & poolSupplyAmount
        uint256 p2pSupplyRatePerYear = InterestRatesModel.computeP2PSupplyRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRatePerYear,
                poolBorrowRatePerYear: reserve.currentVariableBorrowRate,
                poolIndex: indexes.poolSupplyIndex,
                p2pIndex: indexes.p2pSupplyIndex,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        (p2pSupplyAmount, poolSupplyAmount) = _getMarketSupply(
            _poolToken,
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex,
            delta
        );

        (avgSupplyRatePerYear, ) = _getWeightedRate(
            p2pSupplyRatePerYear,
            poolSupplyRatePerYear,
            p2pSupplyAmount,
            poolSupplyAmount
        );
    }

    /// @notice Computes and returns the current average borrow rate per year experienced on a given market.
    /// @param _poolToken The market address.
    /// @return avgBorrowRatePerYear The market's average borrow rate per year (in ray).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getAverageBorrowRatePerYear(address _poolToken)
        public
        view
        returns (
            uint256 avgBorrowRatePerYear,
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount
        )
    {
        (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        ) = _getIndexes(_poolToken);

        DataTypes.ReserveData memory reserve = pool.getReserveData(market.underlyingToken);
        uint256 poolBorrowRatePerYear = reserve.currentVariableBorrowRate;

        // Do not take delta into account as it's already taken into account in p2pBorrowAmount & poolBorrowAmount
        uint256 p2pBorrowRatePerYear = InterestRatesModel.computeP2PBorrowRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                poolSupplyRatePerYear: reserve.currentLiquidityRate,
                poolBorrowRatePerYear: poolBorrowRatePerYear,
                poolIndex: indexes.poolBorrowIndex,
                p2pIndex: indexes.p2pBorrowIndex,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        (p2pBorrowAmount, poolBorrowAmount) = _getMarketBorrow(
            reserve,
            indexes.p2pBorrowIndex,
            indexes.poolBorrowIndex,
            delta
        );

        (avgBorrowRatePerYear, ) = _getWeightedRate(
            p2pBorrowRatePerYear,
            poolBorrowRatePerYear,
            p2pBorrowAmount,
            poolBorrowAmount
        );
    }

    /// @notice Computes and returns peer-to-peer and pool rates for a specific market.
    /// @dev Note: prefer using getAverageSupplyRatePerYear & getAverageBorrowRatePerYear to get the actual experienced supply/borrow rate.
    /// @param _poolToken The market address.
    /// @return p2pSupplyRate The market's peer-to-peer supply rate per year (in ray).
    /// @return p2pBorrowRate The market's peer-to-peer borrow rate per year (in ray).
    /// @return poolSupplyRate The market's pool supply rate per year (in ray).
    /// @return poolBorrowRate The market's pool borrow rate per year (in ray).
    function getRatesPerYear(address _poolToken)
        public
        view
        returns (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        )
    {
        (
            Types.Market memory market,
            Types.Delta memory delta,
            Types.Indexes memory indexes
        ) = _getIndexes(_poolToken);

        DataTypes.ReserveData memory reserve = pool.getReserveData(market.underlyingToken);
        poolSupplyRate = reserve.currentLiquidityRate;
        poolBorrowRate = reserve.currentVariableBorrowRate;

        p2pSupplyRate = InterestRatesModel.computeP2PSupplyRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: indexes.poolSupplyIndex,
                p2pIndex: indexes.p2pSupplyIndex,
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        p2pBorrowRate = InterestRatesModel.computeP2PBorrowRatePerYear(
            InterestRatesModel.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: indexes.poolBorrowIndex,
                p2pIndex: indexes.p2pBorrowIndex,
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
    }

    /// INTERNAL ///

    /// @notice Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @param _p2pSupplyIndex The given market's peer-to-peer supply index.
    /// @param _poolSupplyIndex The given market's pool supply index.
    /// @param _delta The given market's deltas.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function _getMarketSupply(
        address _poolToken,
        uint256 _p2pSupplyIndex,
        uint256 _poolSupplyIndex,
        Types.Delta memory _delta
    ) internal view returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount) {
        p2pSupplyAmount = _delta.p2pSupplyAmount.rayMul(_p2pSupplyIndex).zeroFloorSub(
            _delta.p2pSupplyDelta.rayMul(_poolSupplyIndex)
        );
        poolSupplyAmount = IAToken(_poolToken).balanceOf(address(morpho));
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param reserve The reserve data of the underlying pool.
    /// @param _p2pBorrowIndex The given market's peer-to-peer borrow index.
    /// @param _poolBorrowIndex The given market's pool borrow index.
    /// @param _delta The given market's deltas.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function _getMarketBorrow(
        DataTypes.ReserveData memory reserve,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex,
        Types.Delta memory _delta
    ) internal view returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) {
        p2pBorrowAmount = _delta.p2pBorrowAmount.rayMul(_p2pBorrowIndex).zeroFloorSub(
            _delta.p2pBorrowDelta.rayMul(_poolBorrowIndex)
        );
        poolBorrowAmount = IVariableDebtToken(reserve.variableDebtTokenAddress)
        .scaledBalanceOf(address(morpho))
        .rayMul(_poolBorrowIndex);
    }

    /// @dev Returns the supply rate per year experienced on a market based on a given position distribution.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool`).
    /// @return The supply rate per year experienced by the given position (in ray).
    /// @return The sum of peer-to-peer & pool balances.
    function _getUserSupplyRatePerYear(
        address _poolToken,
        uint256 _balanceInP2P,
        uint256 _balanceOnPool
    ) internal view returns (uint256, uint256) {
        (uint256 p2pSupplyRatePerYear, , uint256 poolSupplyRatePerYear, ) = getRatesPerYear(
            _poolToken
        );

        return
            _getWeightedRate(
                p2pSupplyRatePerYear,
                poolSupplyRatePerYear,
                _balanceInP2P,
                _balanceOnPool
            );
    }

    /// @dev Returns the borrow rate per year experienced on a market based on a given position distribution.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool`).
    /// @return The borrow rate per year experienced by the given position (in ray).
    /// @return The sum of peer-to-peer & pool balances.
    function _getUserBorrowRatePerYear(
        address _poolToken,
        uint256 _balanceInP2P,
        uint256 _balanceOnPool
    ) internal view returns (uint256, uint256) {
        (, uint256 p2pBorrowRatePerYear, , uint256 poolBorrowRatePerYear) = getRatesPerYear(
            _poolToken
        );

        return
            _getWeightedRate(
                p2pBorrowRatePerYear,
                poolBorrowRatePerYear,
                _balanceInP2P,
                _balanceOnPool
            );
    }

    /// @dev Returns the rate experienced based on a given pool & peer-to-peer distribution.
    /// @param _p2pRate The peer-to-peer rate (in a unit common to `_poolRate` & `weightedRate`).
    /// @param _poolRate The pool rate (in a unit common to `_p2pRate` & `weightedRate`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool`).
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P`).
    /// @return weightedRate The rate experienced by the given distribution (in a unit common to `_p2pRate` & `_poolRate`).
    /// @return totalBalance The sum of peer-to-peer & pool balances.
    function _getWeightedRate(
        uint256 _p2pRate,
        uint256 _poolRate,
        uint256 _balanceInP2P,
        uint256 _balanceOnPool
    ) internal pure returns (uint256 weightedRate, uint256 totalBalance) {
        totalBalance = _balanceInP2P + _balanceOnPool;
        if (totalBalance == 0) return (weightedRate, totalBalance);

        if (_balanceInP2P > 0) weightedRate += _p2pRate.rayMul(_balanceInP2P.rayDiv(totalBalance));
        if (_balanceOnPool > 0)
            weightedRate += _poolRate.rayMul(_balanceOnPool.rayDiv(totalBalance));
    }
}
