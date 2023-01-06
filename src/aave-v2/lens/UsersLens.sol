// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "./IndexesLens.sol";

/// @title UsersLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract UsersLens is IndexesLens {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using Math for uint256;

    /// EXTERNAL ///

    /// @notice Returns all markets entered by a given user.
    /// @param _user The address of the user.
    /// @return enteredMarkets The list of markets entered by this user.
    function getEnteredMarkets(address _user)
        external
        view
        returns (address[] memory enteredMarkets)
    {
        address[] memory createdMarkets = morpho.getMarketsCreated();
        uint256 nbCreatedMarkets = createdMarkets.length;

        uint256 nbEnteredMarkets;
        enteredMarkets = new address[](nbCreatedMarkets);

        bytes32 userMarkets = morpho.userMarkets(_user);
        for (uint256 i; i < nbCreatedMarkets; ++i) {
            if (_isSupplyingOrBorrowing(userMarkets, createdMarkets[i])) {
                enteredMarkets[nbEnteredMarkets] = createdMarkets[i];
                ++nbEnteredMarkets;
            }
        }

        // Resize the array for return
        assembly {
            mstore(enteredMarkets, nbEnteredMarkets)
        }
    }

    /// @notice Returns the maximum amount available to withdraw & borrow for a given user, on a given market.
    /// @param _user The user to determine the capacities for.
    /// @param _poolToken The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolToken)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        Types.LiquidityData memory liquidityData = getUserBalanceStates(_user);
        Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
            _user,
            _poolToken,
            oracle
        );

        if (
            liquidityData.debtEth > 0 &&
            liquidityData.maxDebtEth.wadDiv(liquidityData.debtEth) <=
            HEALTH_FACTOR_LIQUIDATION_THRESHOLD
        ) return (0, 0);

        uint256 poolTokenBalance = ERC20(IAToken(_poolToken).UNDERLYING_ASSET_ADDRESS()).balanceOf(
            _poolToken
        );

        if (liquidityData.debtEth < liquidityData.borrowableEth)
            borrowable = Math.min(
                poolTokenBalance,
                ((liquidityData.borrowableEth - liquidityData.debtEth) * assetData.tokenUnit) /
                    assetData.underlyingPrice
            );

        withdrawable = Math.min(
            poolTokenBalance,
            (assetData.collateralEth * assetData.tokenUnit) / assetData.underlyingPrice
        );

        if (assetData.liquidationThreshold > 0)
            withdrawable = Math.min(
                withdrawable,
                ((liquidityData.maxDebtEth - liquidityData.debtEth).percentDiv(
                    assetData.liquidationThreshold
                ) * assetData.tokenUnit) / assetData.underlyingPrice
            );
    }

    /// @dev Computes the maximum repayable amount for a potential liquidation.
    /// @param _user The potential liquidatee.
    /// @param _poolTokenBorrowed The address of the market to repay.
    /// @param _poolTokenCollateral The address of the market to seize.
    /// @return The maximum repayable amount (in underlying).
    function computeLiquidationRepayAmount(
        address _user,
        address _poolTokenBorrowed,
        address _poolTokenCollateral
    ) external view returns (uint256) {
        if (!isLiquidatable(_user, _poolTokenBorrowed)) return 0;

        (
            address collateralToken,
            ,
            ,
            uint256 totalCollateralBalance
        ) = _getCurrentSupplyBalanceInOf(_poolTokenCollateral, _user);
        (address borrowedToken, , , uint256 totalBorrowBalance) = _getCurrentBorrowBalanceInOf(
            _poolTokenBorrowed,
            _user
        );

        (, , uint256 liquidationBonus, uint256 collateralReserveDecimals, ) = pool
        .getConfiguration(collateralToken)
        .getParamsMemory();

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        uint256 borrowedPrice = oracle.getAssetPrice(borrowedToken);
        uint256 collateralPrice = oracle.getAssetPrice(collateralToken);

        return
            Math.min(
                ((totalCollateralBalance * collateralPrice * 10**ERC20(borrowedToken).decimals()) /
                    (borrowedPrice * 10**collateralReserveDecimals))
                    .percentDiv(liquidationBonus),
                totalBorrowBalance.percentMul(DEFAULT_LIQUIDATION_CLOSE_FACTOR)
            );
    }

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to determine balances of.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentSupplyBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (, balanceInP2P, balanceOnPool, totalBalance) = _getCurrentSupplyBalanceInOf(
            _poolToken,
            _user
        );
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to determine balances of.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentBorrowBalanceInOf(address _poolToken, address _user)
        external
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (, balanceInP2P, balanceOnPool, totalBalance) = _getCurrentBorrowBalanceInOf(
            _poolToken,
            _user
        );
    }

    /// PUBLIC ///

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @return The liquidity data of the user.
    function getUserBalanceStates(address _user) public view returns (Types.LiquidityData memory) {
        return getUserHypotheticalBalanceStates(_user, address(0), 0, 0);
    }

    /// @notice Returns the aggregated position of a given user, following an hypothetical borrow/withdraw on a given market,
    ///         using virtually updated pool & peer-to-peer indexes for all markets.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw from the given market (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow from the given market (in underlying).
    /// @return liquidityData The liquidity data of the user.
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public view returns (Types.LiquidityData memory liquidityData) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        address[] memory createdMarkets = morpho.getMarketsCreated();
        bytes32 userMarkets = morpho.userMarkets(_user);

        uint256 nbCreatedMarkets = createdMarkets.length;
        for (uint256 i; i < nbCreatedMarkets; ++i) {
            address poolToken = createdMarkets[i];

            if (!_isSupplyingOrBorrowing(userMarkets, poolToken) && _poolToken != poolToken)
                continue;

            Types.AssetLiquidityData memory assetData = _poolToken == poolToken
                ? _getUserHypotheticalLiquidityDataForAsset(
                    _user,
                    poolToken,
                    oracle,
                    _withdrawnAmount,
                    _borrowedAmount
                )
                : _getUserHypotheticalLiquidityDataForAsset(_user, poolToken, oracle, 0, 0);

            liquidityData.collateralEth += assetData.collateralEth;
            liquidityData.borrowableEth += assetData.collateralEth.percentMul(assetData.ltv);
            liquidityData.maxDebtEth += assetData.collateralEth.percentMul(
                assetData.liquidationThreshold
            );
            liquidityData.debtEth += assetData.debtEth;
        }
    }

    /// @notice Returns the data related to `_poolToken` for the `_user`.
    /// @param _user The user to determine data for.
    /// @param _poolToken The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolToken,
        IPriceOracleGetter _oracle
    ) public view returns (Types.AssetLiquidityData memory) {
        return _getUserHypotheticalLiquidityDataForAsset(_user, _poolToken, _oracle, 0, 0);
    }

    /// @notice Returns the health factor of a given user, using virtually updated pool & peer-to-peer indexes for all markets.
    /// @param _user The user of whom to get the health factor.
    /// @return The health factor of the given user (in wad).
    function getUserHealthFactor(address _user) public view returns (uint256) {
        return getUserHypotheticalHealthFactor(_user, address(0), 0, 0);
    }

    /// @notice Returns the hypothetical health factor of a user, following an hypothetical borrow/withdraw on a given market,
    ///         using virtually updated pool & peer-to-peer indexes for all markets.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw/borrow from.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return healthFactor The health factor of the user.
    function getUserHypotheticalHealthFactor(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public view returns (uint256 healthFactor) {
        Types.LiquidityData memory liquidityData = getUserHypotheticalBalanceStates(
            _user,
            _poolToken,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (liquidityData.debtEth == 0) return type(uint256).max;

        return liquidityData.maxDebtEth.wadDiv(liquidityData.debtEth);
    }

    /// @notice Returns whether a liquidation can be performed on a given user, based on their health factor.
    /// @dev This function checks for the user's health factor, without treating borrow positions from deprecated market as instantly liquidatable.
    /// @param _user The address of the user to check.
    /// @return whether or not the user is liquidatable.
    function isLiquidatable(address _user) public view returns (bool) {
        return getUserHealthFactor(_user) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /// @notice Returns whether a liquidation can be performed on a given user borrowing from a given market.
    /// @dev This function checks for the user's health factor as well as whether the given market is deprecated & the user is borrowing from it.
    /// @param _user The address of the user to check.
    /// @param _poolToken The address of the borrowed market to check.
    /// @return whether or not the user is liquidatable.
    function isLiquidatable(address _user, address _poolToken) public view returns (bool) {
        if (morpho.marketPauseStatus(_poolToken).isDeprecated && _isBorrowing(_user, _poolToken))
            return true;

        return isLiquidatable(_user);
    }

    /// INTERNAL ///

    /// @dev Returns wheter the given user is borrowing from the given market.
    /// @param _user The address of the user to check.
    /// @param _market The address of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isBorrowing(address _user, address _market) internal view returns (bool) {
        return morpho.userMarkets(_user) & morpho.borrowMask(_market) != 0;
    }

    /// @dev Returns whether the given user is borrowing or supplying on the given market.
    /// @param _userMarkets The bytes representation of entered markets of the user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isSupplyingOrBorrowing(bytes32 _userMarkets, address _market)
        internal
        view
        returns (bool)
    {
        bytes32 marketBorrowMask = morpho.borrowMask(_market);

        return _userMarkets & (marketBorrowMask | (marketBorrowMask << 1)) != 0;
    }

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to determine balances of.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getCurrentSupplyBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (
            address underlyingToken,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (Types.Market memory market, , Types.Indexes memory indexes) = _getIndexes(_poolToken);

        underlyingToken = market.underlyingToken;
        (balanceInP2P, balanceOnPool, totalBalance) = _getSupplyBalanceInOf(
            _poolToken,
            _user,
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex
        );
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to determine balances of.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getCurrentBorrowBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (
            address underlyingToken,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (Types.Market memory market, , Types.Indexes memory indexes) = _getIndexes(_poolToken);

        underlyingToken = market.underlyingToken;
        (balanceInP2P, balanceOnPool, totalBalance) = _getBorrowBalanceInOf(
            _poolToken,
            _user,
            indexes.p2pBorrowIndex,
            indexes.poolBorrowIndex
        );
    }

    /// @dev Returns the supply balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param _poolToken The market where to get the supply amount.
    /// @param _user The address of the user.
    /// @param _p2pSupplyIndex The peer-to-peer supply index of the given market (in ray).
    /// @param _poolSupplyIndex The pool supply index of the given market (in ray).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getSupplyBalanceInOf(
        address _poolToken,
        address _user,
        uint256 _p2pSupplyIndex,
        uint256 _poolSupplyIndex
    )
        internal
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(_poolToken, _user);

        balanceInP2P = supplyBalance.inP2P.rayMul(_p2pSupplyIndex);
        balanceOnPool = supplyBalance.onPool.rayMul(_poolSupplyIndex);

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolToken` market.
    /// @param _poolToken The market where to get the borrow amount.
    /// @param _user The address of the user.
    /// @param _p2pBorrowIndex The peer-to-peer borrow index of the given market (in ray).
    /// @param _poolBorrowIndex The pool borrow index of the given market (in ray).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getBorrowBalanceInOf(
        address _poolToken,
        address _user,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex
    )
        internal
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(_poolToken, _user);

        balanceInP2P = borrowBalance.inP2P.rayMul(_p2pBorrowIndex);
        balanceOnPool = borrowBalance.onPool.rayMul(_poolBorrowIndex);

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @notice Returns the data related to `_poolToken` for the `_user`.
    /// @param _user The user to determine data for.
    /// @param _poolToken The address of the market.
    /// @param _oracle The oracle used.
    /// @param _withdrawnAmount The amount to hypothetically withdraw from the given market (in underlying).
    /// @param _borrowedAmount The amount to hypothetically borrow from the given market (in underlying).
    /// @return assetData The data related to this asset.
    function _getUserHypotheticalLiquidityDataForAsset(
        address _user,
        address _poolToken,
        IPriceOracleGetter _oracle,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal view returns (Types.AssetLiquidityData memory assetData) {
        (Types.Market memory market, , Types.Indexes memory indexes) = _getIndexes(_poolToken);

        assetData.underlyingPrice = _oracle.getAssetPrice(market.underlyingToken); // In ETH.
        (assetData.ltv, assetData.liquidationThreshold, , assetData.decimals, ) = pool
        .getConfiguration(market.underlyingToken)
        .getParamsMemory();

        unchecked {
            assetData.tokenUnit = 10**assetData.decimals;
        }

        (, , uint256 totalCollateralBalance) = _getSupplyBalanceInOf(
            _poolToken,
            _user,
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex
        );
        (, , uint256 totalDebtBalance) = _getBorrowBalanceInOf(
            _poolToken,
            _user,
            indexes.p2pBorrowIndex,
            indexes.poolBorrowIndex
        );

        assetData.debtEth = ((totalDebtBalance + _borrowedAmount) * assetData.underlyingPrice)
        .divUp(assetData.tokenUnit);
        assetData.collateralEth =
            ((totalCollateralBalance.zeroFloorSub(_withdrawnAmount)) * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }
}
