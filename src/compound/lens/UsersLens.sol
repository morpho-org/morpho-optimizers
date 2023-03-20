// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./IndexesLens.sol";

/// @title UsersLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract UsersLens is IndexesLens {
    using CompoundMath for uint256;
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
        return morpho.getEnteredMarkets(_user);
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
        Types.LiquidityData memory data;
        Types.AssetLiquidityData memory assetData;
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        for (uint256 i; i < enteredMarkets.length; ) {
            address poolTokenEntered = enteredMarkets[i];

            if (_poolToken != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, false, oracle);

                data.maxDebtUsd += assetData.maxDebtUsd;
                data.debtUsd += assetData.debtUsd;
            }

            unchecked {
                ++i;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolToken, true, oracle);

        data.maxDebtUsd += assetData.maxDebtUsd;
        data.debtUsd += assetData.debtUsd;

        // Not possible to withdraw nor borrow.
        if (data.maxDebtUsd < data.debtUsd) return (0, 0);

        uint256 poolTokenBalance = _poolToken == morpho.cEth()
            ? _poolToken.balance
            : ERC20(ICToken(_poolToken).underlying()).balanceOf(_poolToken);

        borrowable = Math.min(
            poolTokenBalance,
            (data.maxDebtUsd - data.debtUsd).div(assetData.underlyingPrice)
        );
        withdrawable = Math.min(
            poolTokenBalance,
            assetData.collateralUsd.div(assetData.underlyingPrice)
        );

        if (assetData.collateralFactor != 0) {
            withdrawable = Math.min(withdrawable, borrowable.div(assetData.collateralFactor));
        }
    }

    /// @dev Computes the maximum repayable amount for a potential liquidation.
    /// @param _user The potential liquidatee.
    /// @param _poolTokenBorrowed The address of the market to repay.
    /// @param _poolTokenCollateral The address of the market to seize.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    function computeLiquidationRepayAmount(
        address _user,
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address[] calldata _updatedMarkets
    ) external view returns (uint256 toRepay) {
        address[] memory updatedMarkets = new address[](_updatedMarkets.length + 2);

        for (uint256 i; i < _updatedMarkets.length; ) {
            updatedMarkets[i] = _updatedMarkets[i];

            unchecked {
                ++i;
            }
        }

        updatedMarkets[updatedMarkets.length - 2] = _poolTokenBorrowed;
        updatedMarkets[updatedMarkets.length - 1] = _poolTokenCollateral;
        if (!isLiquidatable(_user, _poolTokenBorrowed, updatedMarkets)) return 0;

        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());

        (, , uint256 totalCollateralBalance) = getCurrentSupplyBalanceInOf(
            _poolTokenCollateral,
            _user
        );
        (, , uint256 totalBorrowBalance) = getCurrentBorrowBalanceInOf(_poolTokenBorrowed, _user);

        uint256 borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowed);
        uint256 collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateral);
        if (borrowedPrice == 0 || collateralPrice == 0) revert CompoundOracleFailed();

        uint256 maxROIRepay = totalCollateralBalance.mul(collateralPrice).div(borrowedPrice).div(
            comptroller.liquidationIncentiveMantissa()
        );

        uint256 maxRepayable = totalBorrowBalance.mul(comptroller.closeFactorMantissa());

        toRepay = maxROIRepay > maxRepayable ? maxRepayable : maxROIRepay;
    }

    /// @dev Computes the health factor of a given user, given a list of markets of which to compute virtually updated pool & peer-to-peer indexes.
    /// @param _user The user of whom to get the health factor.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return The health factor of the given user (in wad).
    function getUserHealthFactor(address _user, address[] calldata _updatedMarkets)
        external
        view
        returns (uint256)
    {
        (, uint256 debtUsd, uint256 maxDebtUsd) = getUserBalanceStates(_user, _updatedMarkets);
        if (debtUsd == 0) return type(uint256).max;

        return maxDebtUsd.div(debtUsd);
    }

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The amount to hypothetically withdraw from the given market (in underlying).
    /// @param _borrowedAmount The amount to hypothetically borrow from the given market (in underlying).
    /// @return debtUsd The current debt value of the user (in wad).
    /// @return maxDebtUsd The maximum debt value possible of the user (in wad).
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) external view returns (uint256 debtUsd, uint256 maxDebtUsd) {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory createdMarkets = morpho.getAllMarkets();

        uint256 nbCreatedMarkets = createdMarkets.length;
        for (uint256 i; i < nbCreatedMarkets; ++i) {
            address poolToken = createdMarkets[i];

            Types.AssetLiquidityData memory assetData = _poolToken == poolToken
                ? _getUserHypotheticalLiquidityDataForAsset(
                    _user,
                    poolToken,
                    true,
                    oracle,
                    _withdrawnAmount,
                    _borrowedAmount
                )
                : _getUserHypotheticalLiquidityDataForAsset(_user, poolToken, true, oracle, 0, 0);

            maxDebtUsd += assetData.maxDebtUsd;
            debtUsd += assetData.debtUsd;
        }
    }

    /// PUBLIC ///

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return collateralUsd The collateral value of the user (in wad).
    /// @return debtUsd The current debt value of the user (in wad).
    /// @return maxDebtUsd The maximum possible debt value of the user (in wad).
    function getUserBalanceStates(address _user, address[] calldata _updatedMarkets)
        public
        view
        returns (
            uint256 collateralUsd,
            uint256 debtUsd,
            uint256 maxDebtUsd
        )
    {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < enteredMarkets.length; ) {
            address poolTokenEntered = enteredMarkets[i];

            bool shouldUpdateIndexes;
            for (uint256 j; j < nbUpdatedMarkets; ) {
                if (_updatedMarkets[j] == poolTokenEntered) {
                    shouldUpdateIndexes = true;
                    break;
                }

                unchecked {
                    ++j;
                }
            }

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                shouldUpdateIndexes,
                oracle
            );

            collateralUsd += assetData.collateralUsd;
            maxDebtUsd += assetData.maxDebtUsd;
            debtUsd += assetData.debtUsd;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to determine balances of.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentSupplyBalanceInOf(address _poolToken, address _user)
        public
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(_poolToken, _user);

        balanceOnPool = supplyBalance.onPool.mul(indexes.poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.mul(indexes.p2pSupplyIndex);

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _poolToken The address of the market.
    /// @param _user The user to determine balances of.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getCurrentBorrowBalanceInOf(address _poolToken, address _user)
        public
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        (, Types.Indexes memory indexes) = _getIndexes(_poolToken, true);

        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(_poolToken, _user);

        balanceOnPool = borrowBalance.onPool.mul(indexes.poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.mul(indexes.p2pBorrowIndex);

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @notice Returns the data related to `_poolToken` for the `_user`, by optionally computing virtually updated pool and peer-to-peer indexes.
    /// @param _user The user to determine data for.
    /// @param _poolToken The address of the market.
    /// @param _getUpdatedIndexes Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolToken,
        bool _getUpdatedIndexes,
        ICompoundOracle _oracle
    ) public view returns (Types.AssetLiquidityData memory) {
        return
            _getUserHypotheticalLiquidityDataForAsset(
                _user,
                _poolToken,
                _getUpdatedIndexes,
                _oracle,
                0,
                0
            );
    }

    /// @notice Returns whether a liquidation can be performed on a given user.
    /// @dev This function checks for the user's health factor, without treating borrow positions from deprecated market as instantly liquidatable.
    /// @param _user The address of the user to check.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return whether or not the user is liquidatable.
    function isLiquidatable(address _user, address[] memory _updatedMarkets)
        public
        view
        returns (bool)
    {
        return _isLiquidatable(_user, address(0), _updatedMarkets);
    }

    /// @notice Returns whether a liquidation can be performed on a given user borrowing from a given market.
    /// @dev This function checks for the user's health factor as well as whether the given market is deprecated & the user is borrowing from it.
    /// @param _user The address of the user to check.
    /// @param _poolToken The address of the borrowed market to check.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return whether or not the user is liquidatable.
    function isLiquidatable(
        address _user,
        address _poolToken,
        address[] memory _updatedMarkets
    ) public view returns (bool) {
        if (morpho.marketPauseStatus(_poolToken).isDeprecated)
            return _isLiquidatable(_user, _poolToken, _updatedMarkets);

        return isLiquidatable(_user, _updatedMarkets);
    }

    /// INTERNAL ///

    /// @dev Returns the supply balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param _user The address of the user.
    /// @param _poolToken The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(
        address _poolToken,
        address _user,
        uint256 _p2pSupplyIndex,
        uint256 _poolSupplyIndex
    ) internal view returns (uint256) {
        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(_poolToken, _user);

        return
            supplyBalance.inP2P.mul(_p2pSupplyIndex) + supplyBalance.onPool.mul(_poolSupplyIndex);
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolToken` market.
    /// @param _user The address of the user.
    /// @param _poolToken The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(
        address _poolToken,
        address _user,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex
    ) internal view returns (uint256) {
        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(_poolToken, _user);

        return
            borrowBalance.inP2P.mul(_p2pBorrowIndex) + borrowBalance.onPool.mul(_poolBorrowIndex);
    }

    /// @dev Returns the data related to `_poolToken` for the `_user`, by optionally computing virtually updated pool and peer-to-peer indexes.
    /// @param _user The user to determine data for.
    /// @param _poolToken The address of the market.
    /// @param _getUpdatedIndexes Whether to compute virtually updated pool and peer-to-peer indexes.
    /// @param _oracle The oracle used.
    /// @param _withdrawnAmount The amount to hypothetically withdraw from the given market (in underlying).
    /// @param _borrowedAmount The amount to hypothetically borrow from the given market (in underlying).
    /// @return assetData The data related to this asset.
    function _getUserHypotheticalLiquidityDataForAsset(
        address _user,
        address _poolToken,
        bool _getUpdatedIndexes,
        ICompoundOracle _oracle,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal view returns (Types.AssetLiquidityData memory assetData) {
        assetData.underlyingPrice = _oracle.getUnderlyingPrice(_poolToken);
        if (assetData.underlyingPrice == 0) revert CompoundOracleFailed();

        (, assetData.collateralFactor, ) = comptroller.markets(_poolToken);

        (, Types.Indexes memory indexes) = _getIndexes(_poolToken, _getUpdatedIndexes);

        assetData.collateralUsd = _getUserSupplyBalanceInOf(
            _poolToken,
            _user,
            indexes.p2pSupplyIndex,
            indexes.poolSupplyIndex
        ).zeroFloorSub(_withdrawnAmount)
        .mul(assetData.underlyingPrice);

        assetData.debtUsd = (_getUserBorrowBalanceInOf(
            _poolToken,
            _user,
            indexes.p2pBorrowIndex,
            indexes.poolBorrowIndex
        ) + _borrowedAmount)
        .mul(assetData.underlyingPrice);

        assetData.maxDebtUsd = assetData.collateralUsd.mul(assetData.collateralFactor);
    }

    /// @dev Returns whether a liquidation can be performed on the given user.
    ///      This function checks for the user's health factor as well as whether the user is borrowing from the given deprecated market.
    /// @param _user The address of the user to check.
    /// @param _poolTokenDeprecated The address of the deprecated borrowed market to check.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return whether or not the user is liquidatable.
    function _isLiquidatable(
        address _user,
        address _poolTokenDeprecated,
        address[] memory _updatedMarkets
    ) internal view returns (bool) {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 maxDebtUsd;
        uint256 debtUsd;

        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < enteredMarkets.length; ) {
            address poolTokenEntered = enteredMarkets[i];

            bool shouldUpdateIndexes;
            for (uint256 j; j < nbUpdatedMarkets; ) {
                if (_updatedMarkets[j] == poolTokenEntered) {
                    shouldUpdateIndexes = true;
                    break;
                }

                unchecked {
                    ++j;
                }
            }

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                shouldUpdateIndexes,
                oracle
            );

            if (_poolTokenDeprecated == poolTokenEntered && assetData.debtUsd > 0) return true;

            maxDebtUsd += assetData.maxDebtUsd;
            debtUsd += assetData.debtUsd;

            unchecked {
                ++i;
            }
        }

        return debtUsd > maxDebtUsd;
    }
}
