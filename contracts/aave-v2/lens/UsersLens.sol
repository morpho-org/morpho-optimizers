// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

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

    /// ERRORS ///

    /// @notice Thrown when the Compound's oracle failed.
    error CompoundOracleFailed();

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
        for (uint256 i; i < nbCreatedMarkets; i++) {
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

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @param _user The user to determine the capacities for.
    /// @param _poolTokenAddress The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        Types.LiquidityData memory data;
        Types.AssetLiquidityData memory assetData;
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        address[] memory createdMarkets = morpho.getMarketsCreated();
        bytes32 userMarkets = morpho.userMarkets(_user);

        uint256 nbCreatedMarkets = createdMarkets.length;
        for (uint256 i; i < nbCreatedMarkets; ) {
            address poolToken = createdMarkets[i];

            if (_poolTokenAddress != poolToken && _isSupplyingOrBorrowing(userMarkets, poolToken)) {
                assetData = getUserLiquidityDataForAsset(_user, poolToken, oracle);

                data.collateralValue += assetData.collateralValue;
                data.debtValue += assetData.debtValue;
                data.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);
                data.liquidationThresholdValue += assetData.collateralValue.percentMul(
                    assetData.liquidationThreshold
                );
            }

            unchecked {
                ++i;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        data.collateralValue += assetData.collateralValue;
        data.debtValue += assetData.debtValue;
        data.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);
        data.liquidationThresholdValue += assetData.collateralValue.percentMul(
            assetData.liquidationThreshold
        );

        data.healthFactor = data.debtValue == 0
            ? type(uint256).max
            : data.liquidationThresholdValue.wadDiv(data.debtValue);

        // Not possible to withdraw nor borrow.
        if (data.healthFactor <= HEALTH_FACTOR_LIQUIDATION_THRESHOLD) return (0, 0);

        if (data.debtValue == 0)
            withdrawable =
                (assetData.collateralValue * assetData.tokenUnit) /
                assetData.underlyingPrice;
        else
            withdrawable =
                ((data.liquidationThresholdValue - data.debtValue) * assetData.tokenUnit) /
                assetData.underlyingPrice;

        borrowable =
            ((data.maxLoanToValue - data.debtValue) * assetData.tokenUnit) /
            assetData.underlyingPrice;
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
        (, , , uint256 borrowedReserveDecimals, ) = pool
        .getConfiguration(borrowedToken)
        .getParamsMemory();

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        uint256 borrowedPrice = oracle.getAssetPrice(borrowedToken);
        uint256 collateralPrice = oracle.getAssetPrice(collateralToken);

        return
            Math.min(
                ((totalCollateralBalance * collateralPrice * 10**borrowedReserveDecimals) /
                    (borrowedPrice * 10**collateralReserveDecimals))
                    .percentDiv(liquidationBonus),
                totalBorrowBalance.percentMul(DEFAULT_LIQUIDATION_CLOSE_FACTOR)
            );
    }

    /// PUBLIC ///

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to determine balances of.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentSupplyBalanceInOf(address _poolTokenAddress, address _user)
        public
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (, balanceOnPool, balanceInP2P, totalBalance) = _getCurrentSupplyBalanceInOf(
            _poolTokenAddress,
            _user
        );
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to determine balances of.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentBorrowBalanceInOf(address _poolTokenAddress, address _user)
        public
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (, balanceOnPool, balanceInP2P, totalBalance) = _getCurrentBorrowBalanceInOf(
            _poolTokenAddress,
            _user
        );
    }

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @return the liquidity data of the user.
    function getUserBalanceStates(address _user) public view returns (Types.LiquidityData memory) {
        return getUserHypotheticalBalanceStates(_user, address(0), 0, 0);
    }

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return liquidityData The liquidity data of the user.
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
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

                liquidityData.collateralValue += assetData.collateralValue;
                liquidityData.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);
                liquidityData.liquidationThresholdValue += assetData.collateralValue.percentMul(
                    assetData.liquidationThreshold
                );
                liquidityData.debtValue += assetData.debtValue;

                if (_poolTokenAddress == poolToken) {
                    if (_borrowedAmount > 0)
                        liquidityData.debtValue += (_borrowedAmount * assetData.underlyingPrice)
                        .divUp(assetData.tokenUnit);

                    if (_withdrawnAmount > 0) {
                        liquidityData.collateralValue -=
                            (_withdrawnAmount * assetData.underlyingPrice) /
                            assetData.tokenUnit;
                        liquidityData.maxLoanToValue -= ((_withdrawnAmount *
                            assetData.underlyingPrice) / assetData.tokenUnit)
                        .percentMul(assetData.ltv);
                        liquidityData.liquidationThresholdValue -= ((_withdrawnAmount *
                            assetData.underlyingPrice) / assetData.tokenUnit)
                        .percentMul(assetData.liquidationThreshold);
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        liquidityData.healthFactor = liquidityData.debtValue == 0
            ? type(uint256).max
            : liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debtValue);
    }

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        IPriceOracleGetter _oracle
    ) public view returns (Types.AssetLiquidityData memory assetData) {
        (
            address underlyingToken,
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = _getIndexes(_poolTokenAddress);

        assetData.underlyingPrice = _oracle.getAssetPrice(underlyingToken); // In ETH.
        (assetData.ltv, assetData.liquidationThreshold, , assetData.reserveDecimals, ) = pool
        .getConfiguration(underlyingToken)
        .getParamsMemory();

        (, , uint256 totalCollateralBalance) = _getSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            p2pSupplyIndex,
            poolSupplyIndex
        );
        (, , uint256 totalDebtBalance) = _getBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            p2pBorrowIndex,
            poolBorrowIndex
        );

        assetData.tokenUnit = 10**assetData.reserveDecimals;
        assetData.debtValue = (totalDebtBalance * assetData.underlyingPrice).divUp(
            assetData.tokenUnit
        );
        assetData.collateralValue =
            (totalCollateralBalance * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// @dev Computes the health factor of a given user, given a list of markets of which to compute virtually updated pool & peer-to-peer indexes.
    /// @param _user The user of whom to get the health factor.
    /// @return the health factor of the given user (in wad).
    function getUserHealthFactor(address _user) public view returns (uint256) {
        return getUserHypotheticalHealthFactor(_user, address(0), 0, 0);
    }

    /// @dev Returns the hypothetical health factor of a user
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow from.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return healthFactor The health factor of the user.
    function getUserHypotheticalHealthFactor(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public view returns (uint256 healthFactor) {
        Types.LiquidityData memory liquidityData = getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (liquidityData.debtValue == 0) return type(uint256).max;

        return liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debtValue);
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
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to determine balances of.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getCurrentSupplyBalanceInOf(address _poolTokenAddress, address _user)
        public
        view
        returns (
            address underlyingToken,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        (underlyingToken, p2pSupplyIndex, poolSupplyIndex, ) = _getCurrentP2PSupplyIndex(
            _poolTokenAddress
        );

        (balanceOnPool, balanceInP2P, totalBalance) = _getSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            p2pSupplyIndex,
            poolSupplyIndex
        );
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _user The user to determine balances of.
    /// @return underlyingToken The address of the underlying ERC20 token of the given market.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getCurrentBorrowBalanceInOf(address _poolTokenAddress, address _user)
        public
        view
        returns (
            address underlyingToken,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        uint256 p2pBorrowIndex;
        uint256 poolBorrowIndex;
        (underlyingToken, p2pBorrowIndex, , poolBorrowIndex) = _getCurrentP2PBorrowIndex(
            _poolTokenAddress
        );

        (balanceOnPool, balanceInP2P, totalBalance) = _getBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            p2pBorrowIndex,
            poolBorrowIndex
        );
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @param _user The address of the user.
    /// @param _p2pSupplyIndex The peer-to-peer supply index of the given market (in ray).
    /// @param _poolSupplyIndex The pool supply index of the given market (in ray).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getSupplyBalanceInOf(
        address _poolTokenAddress,
        address _user,
        uint256 _p2pSupplyIndex,
        uint256 _poolSupplyIndex
    )
        internal
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(
            _poolTokenAddress,
            _user
        );

        balanceInP2P = supplyBalance.inP2P.rayMul(_p2pSupplyIndex);
        balanceOnPool = supplyBalance.onPool.rayMul(_poolSupplyIndex);

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @param _user The address of the user.
    /// @param _p2pBorrowIndex The peer-to-peer borrow index of the given market (in ray).
    /// @param _poolBorrowIndex The pool borrow index of the given market (in ray).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function _getBorrowBalanceInOf(
        address _poolTokenAddress,
        address _user,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex
    )
        internal
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(
            _poolTokenAddress,
            _user
        );

        balanceInP2P = borrowBalance.inP2P.rayMul(_p2pBorrowIndex);
        balanceOnPool = borrowBalance.onPool.rayMul(_poolBorrowIndex);

        totalBalance = balanceOnPool + balanceInP2P;
    }
}
