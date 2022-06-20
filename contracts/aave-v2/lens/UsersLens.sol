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

    /// ERRORS ///

    /// @notice Thrown when the Compound's oracle failed.
    error CompoundOracleFailed();

    /// EXTERNAL ///

    /// @notice Returns the current balance state of the user.
    /// @param _user The user to determine liquidity for.
    /// @return liquidityData The liquidity data of the user.
    function getUserBalanceStates(address _user)
        external
        view
        returns (Types.LiquidityData memory liquidityData)
    {
        return getUserHypotheticalBalanceStates(_user, address(0), 0, 0);
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
        uint256 numberOfMarketsCreated = createdMarkets.length;

        for (uint256 i; i < numberOfMarketsCreated; ) {
            address poolToken = createdMarkets[i];

            if (_poolTokenAddress != poolToken && _isSupplyingOrBorrowing(_user, poolToken)) {
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
    /// @param _updatedMarkets The list of markets of which to compute virtually updated pool and peer-to-peer indexes.
    // function computeLiquidationRepayAmount(
    //     address _user,
    //     address _poolTokenBorrowedAddress,
    //     address _poolTokenCollateralAddress,
    //     address[] calldata _updatedMarkets
    // ) external view returns (uint256 toRepay) {
    //     address[] memory updatedMarkets = new address[](_updatedMarkets.length + 2);

    //     uint256 nbUpdatedMarkets = _updatedMarkets.length;
    //     for (uint256 i; i < nbUpdatedMarkets; ) {
    //         updatedMarkets[i] = _updatedMarkets[i];

    //         unchecked {
    //             ++i;
    //         }
    //     }

    //     updatedMarkets[updatedMarkets.length - 2] = _poolTokenBorrowedAddress;
    //     updatedMarkets[updatedMarkets.length - 1] = _poolTokenCollateralAddress;
    //     if (!isLiquidatable(_user, updatedMarkets)) return 0;

    //     ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());

    //     (, , uint256 totalCollateralBalance) = getUpdatedUserSupplyBalance(
    //         _user,
    //         _poolTokenCollateralAddress
    //     );
    //     (, , uint256 totalBorrowBalance) = getUpdatedUserBorrowBalance(
    //         _user,
    //         _poolTokenBorrowedAddress
    //     );

    //     uint256 borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
    //     uint256 collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateralAddress);
    //     if (borrowedPrice == 0 || collateralPrice == 0) revert CompoundOracleFailed();

    //     uint256 maxROIRepay = totalCollateralBalance.mul(collateralPrice).div(borrowedPrice).div(
    //         comptroller.liquidationIncentiveMantissa()
    //     );

    //     uint256 maxRepayable = totalBorrowBalance.mul(comptroller.closeFactorMantissa());

    //     toRepay = maxROIRepay > maxRepayable ? maxRepayable : maxROIRepay;
    // }

    /// PUBLIC ///

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param _user The user to determine balances of.
    /// @param _poolTokenAddress The address of the market.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getUpdatedUserSupplyBalance(address _user, address _poolTokenAddress)
        public
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        balanceOnPool = morpho.supplyBalanceInOf(_poolTokenAddress, _user).onPool.rayMul(
            pool.getReserveNormalizedIncome(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS())
        );
        balanceInP2P = morpho.supplyBalanceInOf(_poolTokenAddress, _user).inP2P.rayMul(
            getUpdatedP2PSupplyIndex(_poolTokenAddress)
        );

        totalBalance = balanceOnPool + balanceInP2P;
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param _user The user to determine balances of.
    /// @param _poolTokenAddress The address of the market.
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function getUpdatedUserBorrowBalance(address _user, address _poolTokenAddress)
        public
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        balanceOnPool = morpho.borrowBalanceInOf(_poolTokenAddress, _user).onPool.rayMul(
            pool.getReserveNormalizedVariableDebt(
                IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
            )
        );
        balanceInP2P = morpho.borrowBalanceInOf(_poolTokenAddress, _user).inP2P.rayMul(
            getUpdatedP2PBorrowIndex(_poolTokenAddress)
        );

        totalBalance = balanceOnPool + balanceInP2P;
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
        uint256 numberOfMarketsCreated = createdMarkets.length;

        for (uint256 i; i < numberOfMarketsCreated; ) {
            address poolToken = createdMarkets[i];

            if (_isSupplyingOrBorrowing(_user, poolToken)) {
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
                        liquidityData.debtValue +=
                            (_borrowedAmount * assetData.underlyingPrice) /
                            assetData.tokenUnit;

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
        address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();

        assetData.underlyingPrice = _oracle.getAssetPrice(underlyingAddress); // In ETH.
        (assetData.ltv, assetData.liquidationThreshold, , assetData.reserveDecimals, ) = pool
        .getConfiguration(underlyingAddress)
        .getParamsMemory();
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = getIndexes(_poolTokenAddress);

        assetData.tokenUnit = 10**assetData.reserveDecimals;
        assetData.debtValue =
            (_computeUserBorrowBalanceInOf(
                _poolTokenAddress,
                _user,
                p2pBorrowIndex,
                poolBorrowIndex
            ) * assetData.underlyingPrice) /
            assetData.tokenUnit;
        assetData.collateralValue =
            (_computeUserSupplyBalanceInOf(
                _poolTokenAddress,
                _user,
                p2pSupplyIndex,
                poolSupplyIndex
            ) * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// INTERNAL ///

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isSupplyingOrBorrowing(address _user, address _market) internal view returns (bool) {
        return
            morpho.userMarkets(_user) &
                (morpho.borrowMask(_market) | (morpho.borrowMask(_market) << 1)) !=
            0;
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _computeUserSupplyBalanceInOf(
        address _poolTokenAddress,
        address _user,
        uint256 _p2pSupplyIndex,
        uint256 _poolSupplyIndex
    ) internal view returns (uint256) {
        return
            morpho.supplyBalanceInOf(_poolTokenAddress, _user).inP2P.rayMul(_p2pSupplyIndex) +
            morpho.supplyBalanceInOf(_poolTokenAddress, _user).onPool.rayMul(_poolSupplyIndex);
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _computeUserBorrowBalanceInOf(
        address _poolTokenAddress,
        address _user,
        uint256 _p2pBorrowIndex,
        uint256 _poolBorrowIndex
    ) internal view returns (uint256) {
        return
            morpho.borrowBalanceInOf(_poolTokenAddress, _user).inP2P.rayMul(_p2pBorrowIndex) +
            morpho.borrowBalanceInOf(_poolTokenAddress, _user).onPool.rayMul(_poolBorrowIndex);
    }
}
