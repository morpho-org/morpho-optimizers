// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./UsersLens.sol";

/// @title RatesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract RatesLens is UsersLens {
    using CompoundMath for uint256;
    using Math for uint256;

    /// ERRORS ///

    error BorrowRateFailed();

    /// EXTERNAL ///

    /// @notice Returns the supply rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned supply rate is a low estimate: when supplying through Morpho-Compound,
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

        uint256 repaidToPool;
        if (!morpho.p2pDisabled(_poolToken)) {
            if (delta.p2pBorrowDelta > 0) {
                uint256 matchedDelta = Math.min(
                    delta.p2pBorrowDelta.mul(indexes.poolBorrowIndex),
                    _amount
                );

                supplyBalance.inP2P += matchedDelta.div(indexes.p2pSupplyIndex);
                repaidToPool += matchedDelta;
                _amount -= matchedDelta;
            }

            if (_amount > 0) {
                address firstPoolBorrower = morpho.getHead(
                    _poolToken,
                    Types.PositionType.BORROWERS_ON_POOL
                );
                uint256 firstPoolBorrowerBalance = morpho
                .borrowBalanceInOf(_poolToken, firstPoolBorrower)
                .onPool;

                uint256 matchedP2P = Math.min(
                    firstPoolBorrowerBalance.mul(indexes.poolBorrowIndex),
                    _amount
                );

                supplyBalance.inP2P += matchedP2P.div(indexes.p2pSupplyIndex);
                repaidToPool += matchedP2P;
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) supplyBalance.onPool += _amount.div(indexes.poolSupplyIndex);

        balanceOnPool = supplyBalance.onPool.mul(indexes.poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.mul(indexes.p2pSupplyIndex);

        (nextSupplyRatePerBlock, totalBalance) = _getUserSupplyRatePerBlock(
            _poolToken,
            balanceInP2P,
            balanceOnPool,
            _amount,
            repaidToPool
        );
    }

    /// @notice Returns the borrow rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned borrow rate is a high estimate: when borrowing through Morpho-Compound,
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

        uint256 withdrawnFromPool;
        if (!morpho.p2pDisabled(_poolToken)) {
            if (delta.p2pSupplyDelta > 0) {
                uint256 matchedDelta = Math.min(
                    delta.p2pSupplyDelta.mul(indexes.poolSupplyIndex),
                    _amount
                );

                borrowBalance.inP2P += matchedDelta.div(indexes.p2pBorrowIndex);
                withdrawnFromPool += matchedDelta;
                _amount -= matchedDelta;
            }

            if (_amount > 0) {
                address firstPoolSupplier = morpho.getHead(
                    _poolToken,
                    Types.PositionType.SUPPLIERS_ON_POOL
                );
                uint256 firstPoolSupplierBalance = morpho
                .supplyBalanceInOf(_poolToken, firstPoolSupplier)
                .onPool;

                uint256 matchedP2P = Math.min(
                    firstPoolSupplierBalance.mul(indexes.poolSupplyIndex),
                    _amount
                );

                borrowBalance.inP2P += matchedP2P.div(indexes.p2pBorrowIndex);
                withdrawnFromPool += matchedP2P;
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) borrowBalance.onPool += _amount.div(indexes.poolBorrowIndex);

        balanceOnPool = borrowBalance.onPool.mul(indexes.poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.mul(indexes.p2pBorrowIndex);

        (nextBorrowRatePerBlock, totalBalance) = _getUserBorrowRatePerBlock(
            _poolToken,
            balanceInP2P,
            balanceOnPool,
            _amount,
            withdrawnFromPool
        );
    }

    /// @notice Returns the supply rate per block a given user is currently experiencing on a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to compute the supply rate per block for.
    /// @return supplyRatePerBlock The supply rate per block the user is currently experiencing (in wad).
    function getCurrentUserSupplyRatePerBlock(address _poolToken, address _user)
        external
        view
        returns (uint256 supplyRatePerBlock)
    {
        (uint256 balanceOnPool, uint256 balanceInP2P, ) = getCurrentSupplyBalanceInOf(
            _poolToken,
            _user
        );

        (supplyRatePerBlock, ) = _getUserSupplyRatePerBlock(
            _poolToken,
            balanceInP2P,
            balanceOnPool,
            0,
            0
        );
    }

    /// @notice Returns the borrow rate per block a given user is currently experiencing on a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to compute the borrow rate per block for.
    /// @return borrowRatePerBlock The borrow rate per block the user is currently experiencing (in wad).
    function getCurrentUserBorrowRatePerBlock(address _poolToken, address _user)
        external
        view
        returns (uint256 borrowRatePerBlock)
    {
        (uint256 balanceOnPool, uint256 balanceInP2P, ) = getCurrentBorrowBalanceInOf(
            _poolToken,
            _user
        );

        (borrowRatePerBlock, ) = _getUserBorrowRatePerBlock(
            _poolToken,
            balanceInP2P,
            balanceOnPool,
            0,
            0
        );
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

        (avgSupplyRatePerBlock, ) = _getWeightedRate(
            p2pSupplyRate,
            poolSupplyRate,
            p2pSupplyAmount,
            poolSupplyAmount
        );
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

        (avgBorrowRatePerBlock, ) = _getWeightedRate(
            p2pBorrowRate,
            poolBorrowRate,
            p2pBorrowAmount,
            poolBorrowAmount
        );
    }

    /// @notice Computes and returns peer-to-peer and pool rates for a specific market.
    /// @dev Note: prefer using getAverageSupplyRatePerBlock & getAverageBorrowRatePerBlock to get the actual experienced supply/borrow rate.
    /// @param _poolToken The market address.
    /// @return p2pSupplyRate The market's peer-to-peer supply rate per block (in wad).
    /// @return p2pBorrowRate The market's peer-to-peer borrow rate per block (in wad).
    /// @return poolSupplyRate The market's pool supply rate per block (in wad).
    /// @return poolBorrowRate The market's pool borrow rate per block (in wad).
    function getRatesPerBlock(address _poolToken)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return _getRatesPerBlock(_poolToken, 0, 0, 0, 0);
    }

    /// INTERNAL ///

    struct PoolRatesVars {
        Types.Delta delta;
        Types.LastPoolIndexes lastPoolIndexes;
        Types.Indexes indexes;
        Types.MarketParameters params;
    }

    /// @dev Computes and returns peer-to-peer and pool rates for a specific market.
    /// @param _poolToken The market address.
    /// @param _suppliedOnPool The amount hypothetically supplied to the underlying's pool (in underlying).
    /// @param _borrowedFromPool The amount hypothetically borrowed from the underlying's pool (in underlying).
    /// @param _repaidOnPool The amount hypothetically repaid to the underlying's pool (in underlying).
    /// @param _withdrawnFromPool The amount hypothetically withdrawn from the underlying's pool (in underlying).
    /// @return p2pSupplyRate The market's peer-to-peer supply rate per block (in wad).
    /// @return p2pBorrowRate The market's peer-to-peer borrow rate per block (in wad).
    /// @return poolSupplyRate The market's pool supply rate per block (in wad).
    /// @return poolBorrowRate The market's pool borrow rate per block (in wad).
    function _getRatesPerBlock(
        address _poolToken,
        uint256 _suppliedOnPool,
        uint256 _borrowedFromPool,
        uint256 _repaidOnPool,
        uint256 _withdrawnFromPool
    )
        internal
        view
        returns (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        )
    {
        PoolRatesVars memory ratesVars;

        ratesVars.delta = morpho.deltas(_poolToken);
        ratesVars.lastPoolIndexes = morpho.lastPoolIndexes(_poolToken);

        bool updated = _suppliedOnPool > 0 ||
            _borrowedFromPool > 0 ||
            _repaidOnPool > 0 ||
            _withdrawnFromPool > 0;
        if (updated) {
            PoolInterestsVars memory interestsVars;
            (
                ratesVars.indexes.poolSupplyIndex,
                ratesVars.indexes.poolBorrowIndex,
                interestsVars
            ) = _accruePoolInterests(ICToken(_poolToken));

            interestsVars.cash =
                interestsVars.cash +
                _suppliedOnPool +
                _repaidOnPool -
                _borrowedFromPool -
                _withdrawnFromPool;
            interestsVars.totalBorrows =
                interestsVars.totalBorrows +
                _borrowedFromPool -
                _repaidOnPool;

            IInterestRateModel interestRateModel = ICToken(_poolToken).interestRateModel();

            poolSupplyRate = IInterestRateModel(interestRateModel).getSupplyRate(
                interestsVars.cash,
                interestsVars.totalBorrows,
                interestsVars.totalReserves,
                interestsVars.reserveFactorMantissa
            );

            (bool success, bytes memory result) = address(interestRateModel).staticcall(
                abi.encodeWithSelector(
                    IInterestRateModel.getBorrowRate.selector,
                    interestsVars.cash,
                    interestsVars.totalBorrows,
                    interestsVars.totalReserves
                )
            );
            if (!success) revert BorrowRateFailed();

            if (result.length > 32) (, poolBorrowRate) = abi.decode(result, (uint256, uint256));
            else poolBorrowRate = abi.decode(result, (uint256));
        } else {
            ratesVars.indexes.poolSupplyIndex = ICToken(_poolToken).exchangeRateStored();
            ratesVars.indexes.poolBorrowIndex = ICToken(_poolToken).borrowIndex();

            poolSupplyRate = ICToken(_poolToken).supplyRatePerBlock();
            poolBorrowRate = ICToken(_poolToken).borrowRatePerBlock();
        }

        (
            ratesVars.indexes.p2pSupplyIndex,
            ratesVars.indexes.p2pBorrowIndex,
            ratesVars.params
        ) = _computeP2PIndexes(
            _poolToken,
            updated,
            ratesVars.indexes.poolSupplyIndex,
            ratesVars.indexes.poolBorrowIndex,
            ratesVars.delta,
            ratesVars.lastPoolIndexes
        );

        uint256 p2pRate = PercentageMath.weightedAvg(
            poolSupplyRate,
            poolBorrowRate,
            ratesVars.params.p2pIndexCursor
        );

        p2pSupplyRate = InterestRatesModel.computeP2PSupplyRatePerBlock(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolSupplyRate,
                poolIndex: ratesVars.indexes.poolSupplyIndex,
                p2pIndex: ratesVars.indexes.p2pSupplyIndex,
                p2pDelta: ratesVars.delta.p2pSupplyDelta,
                p2pAmount: ratesVars.delta.p2pSupplyAmount,
                reserveFactor: ratesVars.params.reserveFactor
            })
        );

        p2pBorrowRate = InterestRatesModel.computeP2PBorrowRatePerBlock(
            InterestRatesModel.P2PRateComputeParams({
                p2pRate: p2pRate,
                poolRate: poolBorrowRate,
                poolIndex: ratesVars.indexes.poolBorrowIndex,
                p2pIndex: ratesVars.indexes.p2pBorrowIndex,
                p2pDelta: ratesVars.delta.p2pBorrowDelta,
                p2pAmount: ratesVars.delta.p2pBorrowAmount,
                reserveFactor: ratesVars.params.reserveFactor
            })
        );
    }

    /// @dev Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
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

    /// @dev Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
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
    ///      The calculation takes into account the change in pool rates implied by an hypothetical supply and/or repay.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool`).
    /// @param _suppliedOnPool The amount hypothetically supplied on pool (in underlying).
    /// @param _repaidToPool The amount hypothetically repaid to the pool (in underlying).
    /// @return The supply rate per block experienced by the given position (in wad).
    /// @return The sum of peer-to-peer & pool balances.
    function _getUserSupplyRatePerBlock(
        address _poolToken,
        uint256 _balanceInP2P,
        uint256 _balanceOnPool,
        uint256 _suppliedOnPool,
        uint256 _repaidToPool
    ) internal view returns (uint256, uint256) {
        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = _getRatesPerBlock(
            _poolToken,
            _suppliedOnPool,
            0,
            0,
            _repaidToPool
        );

        return _getWeightedRate(p2pSupplyRate, poolSupplyRate, _balanceInP2P, _balanceOnPool);
    }

    /// @dev Returns the borrow rate per block experienced on a market based on a given position distribution.
    ///      The calculation takes into account the change in pool rates implied by an hypothetical borrow and/or withdraw.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool`).
    /// @param _borrowedFromPool The amount hypothetically borrowed from the pool (in underlying).
    /// @param _withdrawnFromPool The amount hypothetically withdrawn from the pool (in underlying).
    /// @return The borrow rate per block experienced by the given position (in wad).
    /// @return The sum of peer-to-peer & pool balances.
    function _getUserBorrowRatePerBlock(
        address _poolToken,
        uint256 _balanceInP2P,
        uint256 _balanceOnPool,
        uint256 _borrowedFromPool,
        uint256 _withdrawnFromPool
    ) internal view returns (uint256, uint256) {
        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = _getRatesPerBlock(
            _poolToken,
            0,
            _borrowedFromPool,
            _withdrawnFromPool,
            0
        );

        return _getWeightedRate(p2pBorrowRate, poolBorrowRate, _balanceInP2P, _balanceOnPool);
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

        if (_balanceInP2P > 0) weightedRate += _p2pRate.mul(_balanceInP2P.div(totalBalance));
        if (_balanceOnPool > 0) weightedRate += _poolRate.mul(_balanceOnPool.div(totalBalance));
    }
}
