// SPDX-License-Identifier: GNU AGPLv3
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
        for (uint256 i; i < nbCreatedMarkets; ) {
            if (_isSupplyingOrBorrowing(userMarkets, createdMarkets[i])) {
                enteredMarkets[nbEnteredMarkets] = createdMarkets[i];
                ++nbEnteredMarkets;
            }

            unchecked {
                ++i;
            }
        }

        // Resize the array for return
        assembly {
            mstore(enteredMarkets, nbEnteredMarkets)
        }
    }

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolToken` (in underlyings).
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

        Types.LiquidityData memory liquidityData = getUserHypotheticalBalanceStates(
            _user,
            address(0),
            0,
            0
        );
        Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
            _user,
            _poolToken,
            oracle
        );

        if (
            liquidityData.debt > 0 &&
            liquidityData.liquidationThreshold.wadDiv(liquidityData.debt) <=
            HEALTH_FACTOR_LIQUIDATION_THRESHOLD
        ) return (0, 0);

        uint256 poolTokenBalance = ERC20(IAToken(_poolToken).UNDERLYING_ASSET_ADDRESS()).balanceOf(
            _poolToken
        );

        if (liquidityData.debt < liquidityData.maxDebt)
            borrowable = Math.min(
                poolTokenBalance,
                ((liquidityData.maxDebt - liquidityData.debt) * assetData.tokenUnit) /
                    assetData.underlyingPrice
            );

        withdrawable = Math.min(
            poolTokenBalance,
            (assetData.collateral * assetData.tokenUnit) / assetData.underlyingPrice
        );

        if (assetData.liquidationThreshold > 0)
            withdrawable = Math.min(
                withdrawable,
                ((liquidityData.liquidationThreshold - liquidityData.debt).percentDiv(
                    assetData.liquidationThreshold
                ) * assetData.tokenUnit) / assetData.underlyingPrice
            );
    }

    /// @dev Computes the maximum repayable amount for a potential liquidation.
    /// @param _user The potential liquidatee.
    /// @param _poolTokenBorrowedAddress The address of the market to repay.
    /// @param _poolTokenCollateralAddress The address of the market to seize.
    /// @return The maximum repayable amount (in underlying).
    function computeLiquidationRepayAmount(
        address _user,
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress
    ) external view returns (uint256) {
        if (!isLiquidatable(_user)) return 0;

        (
            address collateralToken,
            ,
            ,
            uint256 totalCollateralBalance
        ) = _getCurrentSupplyBalanceInOf(_poolTokenCollateralAddress, _user);
        (address borrowedToken, , , uint256 totalBorrowBalance) = _getCurrentBorrowBalanceInOf(
            _poolTokenBorrowedAddress,
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

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @return The liquidity data of the user.
    function getUserBalanceStates(address _user)
        external
        view
        returns (Types.LiquidityData memory)
    {
        return getUserHypotheticalBalanceStates(_user, address(0), 0, 0);
    }

    /// PUBLIC ///

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
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
        for (uint256 i; i < nbCreatedMarkets; ) {
            address poolToken = createdMarkets[i];

            if (_isSupplyingOrBorrowing(userMarkets, poolToken)) {
                Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                    _user,
                    poolToken,
                    oracle
                );

                liquidityData.collateral += assetData.collateral;
                liquidityData.maxDebt += assetData.collateral.percentMul(assetData.ltv);
                liquidityData.liquidationThreshold += assetData.collateral.percentMul(
                    assetData.liquidationThreshold
                );
                liquidityData.debt += assetData.debt;

                if (_poolToken == poolToken) {
                    if (_borrowedAmount > 0)
                        liquidityData.debt += (_borrowedAmount * assetData.underlyingPrice).divUp(
                            assetData.tokenUnit
                        );

                    if (_withdrawnAmount > 0) {
                        uint256 assetCollateral = (_withdrawnAmount * assetData.underlyingPrice) /
                            assetData.tokenUnit;

                        liquidityData.collateral -= assetCollateral;
                        liquidityData.maxDebt -= assetCollateral.percentMul(assetData.ltv);
                        liquidityData.liquidationThreshold -= assetCollateral.percentMul(
                            assetData.liquidationThreshold
                        );
                    }
                }
            }

            unchecked {
                ++i;
            }
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
    ) public view returns (Types.AssetLiquidityData memory assetData) {
        (
            address underlyingToken,
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = _getIndexes(_poolToken);

        assetData.underlyingPrice = _oracle.getAssetPrice(underlyingToken); // In ETH.
        (assetData.ltv, assetData.liquidationThreshold, , assetData.decimals, ) = pool
        .getConfiguration(underlyingToken)
        .getParamsMemory();

        (, , uint256 totalCollateralBalance) = _getSupplyBalanceInOf(
            _poolToken,
            _user,
            p2pSupplyIndex,
            poolSupplyIndex
        );
        (, , uint256 totalDebtBalance) = _getBorrowBalanceInOf(
            _poolToken,
            _user,
            p2pBorrowIndex,
            poolBorrowIndex
        );

        assetData.tokenUnit = 10**assetData.decimals;
        assetData.debt = (totalDebtBalance * assetData.underlyingPrice).divUp(assetData.tokenUnit);
        assetData.collateral =
            (totalCollateralBalance * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// @dev Computes the health factor of a given user, given a list of markets of which to compute virtually updated pool & peer-to-peer indexes.
    /// @param _user The user of whom to get the health factor.
    /// @return The health factor of the given user (in wad).
    function getUserHealthFactor(address _user) public view returns (uint256) {
        return getUserHypotheticalHealthFactor(_user, address(0), 0, 0);
    }

    /// @dev Returns the hypothetical health factor of a user
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
        if (liquidityData.debt == 0) return type(uint256).max;

        return liquidityData.liquidationThreshold.wadDiv(liquidityData.debt);
    }

    /// @dev Checks whether a liquidation can be performed on a given user.
    /// @param _user The user to check.
    /// @return whether or not the user is liquidatable.
    function isLiquidatable(address _user) public view returns (bool) {
        return getUserHealthFactor(_user) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /// INTERNAL ///

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _userMarkets The user to check for.
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
        (
            Types.Market memory market,
            uint256 p2pSupplyIndex,
            uint256 poolSupplyIndex,

        ) = _getSupplyIndexes(_poolToken);

        underlyingToken = market.underlyingToken;
        (balanceInP2P, balanceOnPool, totalBalance) = _getSupplyBalanceInOf(
            _poolToken,
            _user,
            p2pSupplyIndex,
            poolSupplyIndex
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
        (
            Types.Market memory market,
            uint256 p2pBorrowIndex,
            ,
            uint256 poolBorrowIndex
        ) = _getBorrowIndexes(_poolToken);

        underlyingToken = market.underlyingToken;
        (balanceInP2P, balanceOnPool, totalBalance) = _getBorrowBalanceInOf(
            _poolToken,
            _user,
            p2pBorrowIndex,
            poolBorrowIndex
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
}
