// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./IndexesLens.sol";

/// @title UsersLens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Intermediary layer exposing endpoints to query live data related to the Morpho Protocol users and their positions.
abstract contract UsersLens is IndexesLens {
    using CompoundMath for uint256;

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

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolToken` (in underlyings).
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
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

        uint256 nbEnteredMarkets = enteredMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            if (_poolToken != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, false, oracle);

                data.maxDebtValue += assetData.maxDebtValue;
                data.debtValue += assetData.debtValue;
            }

            unchecked {
                ++i;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolToken, true, oracle);

        data.maxDebtValue += assetData.maxDebtValue;
        data.debtValue += assetData.debtValue;

        // Not possible to withdraw nor borrow.
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        borrowable = (data.maxDebtValue - data.debtValue).div(assetData.underlyingPrice);
        withdrawable = assetData.collateralValue.div(assetData.underlyingPrice);
        if (assetData.collateralFactor != 0) {
            withdrawable = CompoundMath.min(
                withdrawable,
                borrowable.div(assetData.collateralFactor)
            );
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

        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < nbUpdatedMarkets; ) {
            updatedMarkets[i] = _updatedMarkets[i];

            unchecked {
                ++i;
            }
        }

        updatedMarkets[updatedMarkets.length - 2] = _poolTokenBorrowed;
        updatedMarkets[updatedMarkets.length - 1] = _poolTokenCollateral;
        if (!isLiquidatable(_user, updatedMarkets)) return 0;

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
        (, uint256 debtValue, uint256 maxDebtValue) = getUserBalanceStates(_user, _updatedMarkets);
        if (debtValue == 0) return type(uint256).max;

        return maxDebtValue.div(debtValue);
    }

    /// PUBLIC ///

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return collateralValue The collateral value of the user.
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum possible debt value of the user.
    function getUserBalanceStates(address _user, address[] calldata _updatedMarkets)
        public
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 nbEnteredMarkets = enteredMarkets.length;
        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
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

            collateralValue += assetData.collateralValue;
            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;

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
        (uint256 p2pSupplyIndex, uint256 poolSupplyIndex, ) = _getCurrentP2PSupplyIndex(_poolToken);

        Types.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(_poolToken, _user);

        balanceOnPool = supplyBalance.onPool.mul(poolSupplyIndex);
        balanceInP2P = supplyBalance.inP2P.mul(p2pSupplyIndex);

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
        (uint256 p2pBorrowIndex, , uint256 poolBorrowIndex) = _getCurrentP2PBorrowIndex(_poolToken);

        Types.BorrowBalance memory borrowBalance = morpho.borrowBalanceInOf(_poolToken, _user);

        balanceOnPool = borrowBalance.onPool.mul(poolBorrowIndex);
        balanceInP2P = borrowBalance.inP2P.mul(p2pBorrowIndex);

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum debt value possible of the user.
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public view returns (uint256 debtValue, uint256 maxDebtValue) {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 nbEnteredMarkets = enteredMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[i];

            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                true,
                oracle
            );

            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;
            unchecked {
                ++i;
            }

            if (_poolToken == poolTokenEntered) {
                if (_borrowedAmount > 0)
                    debtValue += _borrowedAmount.mul(assetData.underlyingPrice);

                if (_withdrawnAmount > 0)
                    maxDebtValue -= _withdrawnAmount.mul(assetData.underlyingPrice).mul(
                        assetData.collateralFactor
                    );
            }
        }
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
    ) public view returns (Types.AssetLiquidityData memory assetData) {
        assetData.underlyingPrice = _oracle.getUnderlyingPrice(_poolToken);
        if (assetData.underlyingPrice == 0) revert CompoundOracleFailed();

        (, assetData.collateralFactor, ) = comptroller.markets(_poolToken);

        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = getIndexes(_poolToken, _getUpdatedIndexes);

        assetData.collateralValue = _getUserSupplyBalanceInOf(
            _poolToken,
            _user,
            p2pSupplyIndex,
            poolSupplyIndex
        ).mul(assetData.underlyingPrice);

        assetData.debtValue = _getUserBorrowBalanceInOf(
            _poolToken,
            _user,
            p2pBorrowIndex,
            poolBorrowIndex
        ).mul(assetData.underlyingPrice);

        assetData.maxDebtValue = assetData.collateralValue.mul(assetData.collateralFactor);
    }

    /// @dev Checks whether the user has enough collateral to maintain such a borrow position.
    /// @param _user The user to check.
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    /// @return whether or not the user is liquidatable.
    function isLiquidatable(address _user, address[] memory _updatedMarkets)
        public
        view
        returns (bool)
    {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        address[] memory enteredMarkets = morpho.getEnteredMarkets(_user);

        uint256 maxDebtValue;
        uint256 debtValue;

        uint256 nbEnteredMarkets = enteredMarkets.length;
        uint256 nbUpdatedMarkets = _updatedMarkets.length;
        for (uint256 i; i < nbEnteredMarkets; ) {
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

            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;

            unchecked {
                ++i;
            }
        }

        return debtValue > maxDebtValue;
    }

    /// INTERNAL ///

    /// @dev Returns the supply balance of `_user` in the `_poolToken` market.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
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
}
