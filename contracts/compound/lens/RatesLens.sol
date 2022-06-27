// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";

import "../libraries/CompoundMath.sol";

import "./UsersLens.sol";

/// @title RatesLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract RatesLens is UsersLens {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct Indexes {
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
    }

    /// EXTERNAL ///

    /// @notice Returns the supply rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned supply rate is a lower bound: when supplying through Morpho-Compound,
    /// @dev a supplier could get matched more than once instantly or later and thus benefit from a higher supply rate.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The address of the user on behalf of whom to supply.
    /// @param _amount The amount to supply.
    /// @return nextSupplyRatePerBlock An approximation of the next supply rate per block experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserSupplyRatePerBlock(
        address _poolTokenAddress,
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
                uint256 matchedDelta = CompoundMath.min(deltaInUnderlying, _amount);

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
                uint256 matchedP2P = CompoundMath.min(borrowerBalanceInUnderlying, _amount);

                supplyBalance.inP2P += matchedP2P.div(indexes.p2pSupplyIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) supplyBalance.onPool += _amount.div(indexes.poolSupplyIndex);

        balanceOnPool = supplyBalance.onPool.mul(indexes.poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.mul(indexes.p2pSupplyIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextSupplyRatePerBlock = _computeUserSupplyRatePerBlock(
            _poolTokenAddress,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// @notice Returns the borrow rate per block experienced on a market after having supplied the given amount on behalf of the given user.
    /// @dev Note: the returned borrow rate is an upper bound: when borrowing through Morpho-Compound,
    /// @dev a borrower could get matched more than once instantly or later and thus benefit from a lower borrow rate.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The address of the user on behalf of whom to borrow.
    /// @param _amount The amount to borrow.
    /// @return nextBorrowRatePerBlock An approximation of the next borrow rate per block experienced after having supplied (in wad).
    /// @return balanceOnPool The total balance supplied on pool after having supplied (in underlying).
    /// @return balanceInP2P The total balance matched peer-to-peer after having supplied (in underlying).
    /// @return totalBalance The total balance supplied through Morpho (in underlying).
    function getNextUserBorrowRatePerBlock(
        address _poolTokenAddress,
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
                uint256 matchedDelta = CompoundMath.min(deltaInUnderlying, _amount);

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
                uint256 matchedP2P = CompoundMath.min(supplierBalanceInUnderlying, _amount);

                borrowBalance.inP2P += matchedP2P.div(indexes.p2pBorrowIndex);
                _amount -= matchedP2P;
            }
        }

        if (_amount > 0) borrowBalance.onPool += _amount.div(indexes.poolBorrowIndex);

        balanceOnPool = borrowBalance.onPool.mul(indexes.poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.mul(indexes.p2pBorrowIndex);
        totalBalance = balanceOnPool + balanceInP2P;

        nextBorrowRatePerBlock = _computeUserBorrowRatePerBlock(
            _poolTokenAddress,
            balanceOnPool,
            balanceInP2P,
            totalBalance
        );
    }

    /// PUBLIC ///

    /// @notice Computes and returns the current supply rate per block experienced on average on a given market.
    /// @param _poolTokenAddress The market address.
    /// @return avgSupplyRate The market's average supply rate per block (in wad).
    function getAverageSupplyRatePerBlock(address _poolTokenAddress)
        public
        view
        returns (uint256 avgSupplyRate)
    {
        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = getRatesPerBlock(_poolTokenAddress);
        (uint256 p2pSupplyIndex, , , ) = getIndexes(_poolTokenAddress, false);
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        ICToken poolToken = ICToken(_poolTokenAddress);

        uint256 poolSupply = poolToken.balanceOf(address(morpho)).mul(
            poolToken.exchangeRateStored()
        );
        // don't need to subtract delta as it's already taken into account in the p2pSupplyRate.
        uint256 p2pSupply = delta.p2pSupplyAmount.mul(p2pSupplyIndex);

        uint256 totalSupply = poolSupply + p2pSupply;
        if (poolSupply > 0) avgSupplyRate += poolSupplyRate.mul(poolSupply.div(totalSupply));
        if (p2pSupply > 0) avgSupplyRate += p2pSupplyRate.mul(p2pSupply.div(totalSupply));
    }

    /// @notice Computes and returns the current average borrow rate per block experienced on a given market.
    /// @param _poolTokenAddress The market address.
    /// @return avgBorrowRate The market's average borrow rate per block (in wad).
    function getAverageBorrowRatePerBlock(address _poolTokenAddress)
        public
        view
        returns (uint256 avgBorrowRate)
    {
        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = getRatesPerBlock(_poolTokenAddress);
        (, uint256 p2pBorrowIndex, , ) = getIndexes(_poolTokenAddress, false);
        Types.Delta memory delta = morpho.deltas(_poolTokenAddress);
        ICToken poolToken = ICToken(_poolTokenAddress);

        uint256 poolBorrow = poolToken.borrowBalanceStored(address(morpho));
        // don't need to subtract delta as it's already taken into account in the p2pSupplyRate.
        uint256 p2pBorrow = delta.p2pBorrowAmount.mul(p2pBorrowIndex);

        uint256 totalBorrow = poolBorrow + p2pBorrow;
        if (poolBorrow > 0) avgBorrowRate += poolBorrowRate.mul(poolBorrow.div(totalBorrow));
        if (p2pBorrow > 0) avgBorrowRate += p2pBorrowRate.mul(p2pBorrow.div(totalBorrow));
    }

    /// @notice Computes and returns peer-to-peer and pool rates for a specific market.
    /// @dev Note: prefer using getAverageSupplyRatePerBlock & getAverageBorrowRatePerBlock to get the experienced supply/borrow rate instead of this.
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate_ The market's peer-to-peer supply rate per block (in wad).
    /// @return p2pBorrowRate_ The market's peer-to-peer borrow rate per block (in wad).
    /// @return poolSupplyRate_ The market's pool supply rate per block (in wad).
    /// @return poolBorrowRate_ The market's pool borrow rate per block (in wad).
    function getRatesPerBlock(address _poolTokenAddress)
        public
        view
        returns (
            uint256 p2pSupplyRate_,
            uint256 p2pBorrowRate_,
            uint256 poolSupplyRate_,
            uint256 poolBorrowRate_
        )
    {
        ICToken cToken = ICToken(_poolTokenAddress);

        poolSupplyRate_ = cToken.supplyRatePerBlock();
        poolBorrowRate_ = cToken.borrowRatePerBlock();
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
        ) = getIndexes(_poolTokenAddress, false);

        p2pSupplyRate_ = InterestRatesModel.computeP2PSupplyRatePerBlock(
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

        p2pBorrowRate_ = InterestRatesModel.computeP2PBorrowRatePerBlock(
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
    function getCurrentUserSupplyRatePerBlock(address _poolTokenAddress, address _user)
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
            _computeUserSupplyRatePerBlock(
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
    function getCurrentUserBorrowRatePerBlock(address _poolTokenAddress, address _user)
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
            _computeUserBorrowRatePerBlock(
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
    /// @return supplyRatePerBlock_ The supply rate per block experienced by the given position (in wad).
    function _computeUserSupplyRatePerBlock(
        address _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256 supplyRatePerBlock_) {
        if (_totalBalance == 0) return 0;

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = getRatesPerBlock(_poolTokenAddress);

        if (_balanceOnPool > 0)
            supplyRatePerBlock_ += poolSupplyRate.mul(_balanceOnPool.div(_totalBalance));
        if (_balanceInP2P > 0)
            supplyRatePerBlock_ += p2pSupplyRate.mul(_balanceInP2P.div(_totalBalance));
    }

    /// @dev Returns the borrow rate per block experienced on a market based on a given position distribution.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P` and `_totalBalance`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool` and `_totalBalance`).
    /// @param _totalBalance The total amount of balance (should equal `_balanceOnPool + _balanceInP2P` but is used for saving gas).
    /// @return borrowRatePerBlock_ The borrow rate per block experienced by the given position (in wad).
    function _computeUserBorrowRatePerBlock(
        address _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P,
        uint256 _totalBalance
    ) internal view returns (uint256 borrowRatePerBlock_) {
        if (_totalBalance == 0) return 0;

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = getRatesPerBlock(_poolTokenAddress);

        if (_balanceOnPool > 0)
            borrowRatePerBlock_ += poolBorrowRate.mul(_balanceOnPool.div(_totalBalance));
        if (_balanceInP2P > 0)
            borrowRatePerBlock_ += p2pBorrowRate.mul(_balanceInP2P.div(_totalBalance));
    }
}
