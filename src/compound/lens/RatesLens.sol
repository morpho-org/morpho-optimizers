// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./UsersLens.sol";

/// @title RatesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract RatesLens is UsersLens {
    using CompoundMath for uint256;
    using Math for uint256;

    /// EXTERNAL ///

    /// @notice Returns the supply rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned supply rate is a lower bound: when supplying through Morpho-Compound,
    /// a supplier could be matched more than once instantly or later and thus benefit from a higher supply rate.
    /// @param _poolToken The address of the market.
    /// @param _user The address of the user on behalf of whom to supply.
    /// @param _amount The amount to supply.
    /// @return nextSupplyRatePerBlock An approximation of the next supply rate per block experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserSupplyRatePerBlock(
        address _poolToken,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextSupplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (Types.Delta memory delta, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(_poolToken, _user);
        if (_amount > 0 && delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.mul(indexes.poolBorrowIndex),
                _amount
            );

            supplyBalance.inP2P += matchedDelta.div(indexes.p2pSupplyIndex);
            _amount -= matchedDelta;
        }

        if (_amount > 0 && !morpho.p2pDisabled(_poolToken)) {
            uint256 firstPoolBorrowerBalance = morpho
            .borrowBalanceInOf(
                _poolToken,
                morpho.getHead(_poolToken, Types.PositionType.BORROWERS_ON_POOL)
            ).onPool;

            if (firstPoolBorrowerBalance > 0) {
                uint256 matchedP2P = Math.min(
                    firstPoolBorrowerBalance.mul(indexes.poolBorrowIndex),
                    _amount
                );

                supplyBalance.inP2P += matchedP2P.div(indexes.p2pSupplyIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) supplyBalance.onPool += _amount.div(indexes.poolSupplyIndex);

        balanceOnPool = supplyBalance.onPool.mul(indexes.poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.mul(indexes.p2pSupplyIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextSupplyRatePerBlock = _getUserSupplyRatePerBlock(
            _poolToken,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// @notice Returns the borrow rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned borrow rate is an upper bound: when borrowing through Morpho-Compound,
    /// a borrower could be matched more than once instantly or later and thus benefit from a lower borrow rate.
    /// @param _poolToken The address of the market.
    /// @param _user The address of the user on behalf of whom to borrow.
    /// @param _amount The amount to borrow.
    /// @return nextBorrowRatePerBlock An approximation of the next borrow rate per block experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserBorrowRatePerBlock(
        address _poolToken,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextBorrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (Types.Delta memory delta, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(_poolToken, _user);
        if (_amount > 0 && delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.mul(indexes.poolSupplyIndex),
                _amount
            );

            borrowBalance.inP2P += matchedDelta.div(indexes.p2pBorrowIndex);
            _amount -= matchedDelta;
        }

        if (_amount > 0 && !morpho.p2pDisabled(_poolToken)) {
            uint256 firstPoolSupplierBalance = morpho
            .supplyBalanceInOf(
                _poolToken,
                morpho.getHead(_poolToken, Types.PositionType.SUPPLIERS_ON_POOL)
            ).onPool;

            if (firstPoolSupplierBalance > 0) {
                uint256 matchedP2P = Math.min(
                    firstPoolSupplierBalance.mul(indexes.poolSupplyIndex),
                    _amount
                );

                borrowBalance.inP2P += matchedP2P.div(indexes.p2pBorrowIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) borrowBalance.onPool += _amount.div(indexes.poolBorrowIndex);

        balanceOnPool = borrowBalance.onPool.mul(indexes.poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.mul(indexes.p2pBorrowIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextBorrowRatePerBlock = _getUserBorrowRatePerBlock(
            _poolToken,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// @notice Returns the supply rate per block a given user is currently experiencing on a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to compute the supply rate per block for.
    /// @return The supply rate per block the user is currently experiencing (in wad).
    function getCurrentUserSupplyRatePerBlock(address _poolToken, address _user)
        external
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getCurrentSupplyBalanceInOf(_poolToken, _user);

        return _getUserSupplyRatePerBlock(_poolToken, balanceOnPool, balanceInP2P, totalBalance);
    }

    /// @notice Returns the borrow rate per block a given user is currently experiencing on a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to compute the borrow rate per block for.
    /// @return The borrow rate per block the user is currently experiencing (in wad).
    function getCurrentUserBorrowRatePerBlock(address _poolToken, address _user)
        external
        view
        returns (uint256)
    {
        (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = getCurrentBorrowBalanceInOf(_poolToken, _user);

        return _getUserBorrowRatePerBlock(_poolToken, balanceOnPool, balanceInP2P, totalBalance);
    }

    /// PUBLIC ///

    /// @notice Computes and returns the current supply rate per block experienced on average on a given market.
    /// @param _poolToken The market address.
    /// @return avgSupplyRatePerBlock The market's average supply rate per block (in wad).
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    function getAverageSupplyRatePerBlock(address _poolToken)
        public
        view
        returns (
            uint256 avgSupplyRatePerBlock,
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount
        )
    {
        ICToken cToken = ICToken(_poolToken);

        uint256 poolSupplyRate = cToken.supplyRatePerBlock();
        uint256 poolBorrowRate = cToken.borrowRatePerBlock();

        (Types.Delta memory delta, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);
        // Do not take delta into account as it's already taken into account in p2pSupplyAmount & poolSupplyAmount
        uint256 p2pSupplyRate = InterestRatesModel.computeP2PSupplyRatePerBlock(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: PercentageMath.weightedAvg(
                    poolSupplyRate,
                    poolBorrowRate,
                    marketParams.p2pIndexCursor
                ),
                poolRate: poolSupplyRate,
                poolIndex: indexes.poolSupplyIndex,
                p2pIndex: indexes.p2pSupplyIndex,
                p2pDelta: 0,
                p2pAmount: 0,
                reserveFactor: marketParams.reserveFactor
            })
        );

        (p2pSupplyAmount, poolSupplyAmount) = _getMarketSupply(
            _poolToken,
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex,
            delta
        );

        uint256 totalSupply = p2pSupplyAmount + poolSupplyAmount;
        if (p2pSupplyAmount > 0)
            avgSupplyRatePerBlock += p2pSupplyRate.mul(p2pSupplyAmount.div(totalSupply));
        if (poolSupplyAmount > 0)
            avgSupplyRatePerBlock += poolSupplyRate.mul(poolSupplyAmount.div(totalSupply));
    }

    /// @notice Computes and returns the current average borrow rate per block experienced on a given market.
    /// @param _poolToken The market address.
    /// @return avgBorrowRatePerBlock The market's average borrow rate per block (in wad).
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function getAverageBorrowRatePerBlock(address _poolToken)
        public
        view
        returns (
            uint256 avgBorrowRatePerBlock,
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount
        )
    {
        ICToken cToken = ICToken(_poolToken);

        uint256 poolSupplyRate = cToken.supplyRatePerBlock();
        uint256 poolBorrowRate = cToken.borrowRatePerBlock();

        (Types.Delta memory delta, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);
        // Do not take delta into account as it's already taken into account in p2pBorrowAmount & poolBorrowAmount
        uint256 p2pBorrowRate = InterestRatesModel.computeP2PBorrowRatePerBlock(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: PercentageMath.weightedAvg(
                    poolSupplyRate,
                    poolBorrowRate,
                    marketParams.p2pIndexCursor
                ),
                poolRate: poolBorrowRate,
                poolIndex: indexes.poolBorrowIndex,
                p2pIndex: indexes.p2pBorrowIndex,
                p2pDelta: 0,
                p2pAmount: 0,
                reserveFactor: marketParams.reserveFactor
            })
        );

        (p2pBorrowAmount, poolBorrowAmount) = _getMarketBorrow(
            _poolToken,
            indexes.p2pBorrowIndex,
            indexes.poolBorrowIndex,
            delta
        );

        uint256 totalBorrow = p2pBorrowAmount + poolBorrowAmount;
        if (p2pBorrowAmount > 0)
            avgBorrowRatePerBlock += p2pBorrowRate.mul(p2pBorrowAmount.div(totalBorrow));
        if (poolBorrowAmount > 0)
            avgBorrowRatePerBlock += poolBorrowRate.mul(poolBorrowAmount.div(totalBorrow));
    }

    /// @notice Computes and returns peer-to-peer and pool rates for a specific market.
    /// @dev Note: prefer using getAverageSupplyRatePerBlock & getAverageBorrowRatePerBlock to get the actual experienced supply/borrow rate.
    /// @param _poolToken The market address.
    /// @return p2pSupplyRate The market's peer-to-peer supply rate per block (in wad).
    /// @return p2pBorrowRate The market's peer-to-peer borrow rate per block (in wad).
    /// @return poolSupplyRate The market's pool supply rate per block (in wad).
    /// @return poolBorrowRate The market's pool borrow rate per block (in wad).
    function getRatesPerBlock(address _poolToken)
        public
        view
        returns (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        )
    {
        ICToken cToken = ICToken(_poolToken);

        poolSupplyRate = cToken.supplyRatePerBlock();
        poolBorrowRate = cToken.borrowRatePerBlock();

        Types.MarketParameters memory marketParams = morpho.marketParameters(_poolToken);
        uint256 p2pRate = PercentageMath.weightedAvg(
            poolSupplyRate,
            poolBorrowRate,
            marketParams.p2pIndexCursor
        );

        (Types.Delta memory delta, Types.Indexes memory indexes) = _getIndexes(_poolToken, false);

        p2pSupplyRate = InterestRatesModel.computeP2PSupplyRatePerBlock(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolSupplyRate,
                poolIndex: indexes.poolSupplyIndex,
                p2pIndex: indexes.p2pSupplyIndex,
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount,
                reserveFactor: marketParams.reserveFactor
            })
        );

        p2pBorrowRate = InterestRatesModel.computeP2PBorrowRatePerBlock(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolBorrowRate,
                poolIndex: indexes.poolBorrowIndex,
                p2pIndex: indexes.p2pBorrowIndex,
                p2pDelta: delta.p2pBorrowDelta,
                p2pAmount: delta.p2pBorrowAmount,
                reserveFactor: marketParams.reserveFactor
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
        p2pSupplyAmount = _delta.p2pSupplyAmount.mul(_p2pSupplyIndex).zeroFloorSub(
            _delta.p2pSupplyDelta.mul(_poolSupplyIndex)
        );
        poolSupplyAmount = ICToken(_poolToken).balanceOf(address(morpho)).mul(_poolSupplyIndex);
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param _poolToken The address of the market to check.
    /// @param _p2pBorrowIndex The given market's peer-to-peer borrow index.
    /// @param _poolBorrowIndex The given market's borrow index.
    /// @param _delta The given market's deltas.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function _getMarketBorrow(
        address _poolToken,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex,
        Types.Delta memory _delta
    ) internal view returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) {
        p2pBorrowAmount = _delta.p2pBorrowAmount.mul(_p2pBorrowIndex).zeroFloorSub(
            _delta.p2pBorrowDelta.mul(_poolBorrowIndex)
        );
        poolBorrowAmount = ICToken(_poolToken)
        .borrowBalanceStored(address(morpho))
        .div(ICToken(_poolToken).borrowIndex())
        .mul(_poolBorrowIndex);
    }

    /// @dev Returns the supply rate per block experienced on a market based on a given position distribution.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P` and `_totalBalance`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool` and `_totalBalance`).
    /// @param _totalBalance The total amount of balance (should equal `_balanceOnPool + _balanceInP2P` but is used for saving gas).
    /// @return supplyRatePerBlock_ The supply rate per block experienced by the given position (in wad).
    function _getUserSupplyRatePerBlock(
        address _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256 supplyRatePerBlock_) {
        if (_totalBalance == 0) return 0;

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = getRatesPerBlock(_poolToken);

        if (_balanceOnPool > 0)
            supplyRatePerBlock_ += poolSupplyRate.mul(_balanceOnPool.div(_totalBalance));
        if (_balanceInP2P > 0)
            supplyRatePerBlock_ += p2pSupplyRate.mul(_balanceInP2P.div(_totalBalance));
    }

    /// @dev Returns the borrow rate per block experienced on a market based on a given position distribution.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P` and `_totalBalance`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool` and `_totalBalance`).
    /// @param _totalBalance The total amount of balance (should equal `_balanceOnPool + _balanceInP2P` but is used for saving gas).
    /// @return borrowRatePerBlock_ The borrow rate per block experienced by the given position (in wad).
    function _getUserBorrowRatePerBlock(
        address _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256 borrowRatePerBlock_) {
        if (_totalBalance == 0) return 0;

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = getRatesPerBlock(_poolToken);

        if (_balanceOnPool > 0)
            borrowRatePerBlock_ += poolBorrowRate.mul(_balanceOnPool.div(_totalBalance));
        if (_balanceInP2P > 0)
            borrowRatePerBlock_ += p2pBorrowRate.mul(_balanceInP2P.div(_totalBalance));
    }
}
