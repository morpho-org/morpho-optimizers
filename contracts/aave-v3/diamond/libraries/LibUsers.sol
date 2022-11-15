// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {MorphoStorage as S} from "../storage/MorphoStorage.sol";
import {LibIndexes} from "./LibIndexes.sol";
import {Math, WadRayMath, PercentageMath, DataTypes, ReserveConfiguration, UserConfiguration, Types, EventsAndErrors as E} from "../libraries/Libraries.sol";
import {IPriceOracleGetter} from "../interfaces/Interfaces.sol";

library LibUsers {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using Math for uint256;

    function c() internal pure returns (S.ContractsLayout storage c) {
        return S.contractsLayout();
    }

    function m() internal pure returns (S.MarketsLayout storage m) {
        return S.marketsLayout();
    }

    function p() internal pure returns (S.PositionsLayout storage p) {
        return S.positionsLayout();
    }

    function isSupplyingOrBorrowing(bytes32 _userMarkets, bytes32 _borrowMask)
        internal
        pure
        returns (bool)
    {
        return _userMarkets && (_borrowMask | (_borrowMask << 1)) != 0;
    }

    function isBorrowing(bytes32 _userMarkets, bytes32 _borrowMask) internal pure returns (bool) {
        return _userMarkets & _borrowMask != 0;
    }

    function isSupplying(bytes32 _userMarkets, bytes32 _borrowMask) internal pure returns (bool) {
        return _userMarkets & (_borrowMask << 1) != 0;
    }

    function isBorrowingAny(bytes32 _userMarkets) internal pure returns (bool) {
        return _userMarkets & S.BORROWING_MASK != 0;
    }

    function isBorrowingAndSupplying(
        bytes32 _userMarkets,
        bytes32 _borrowedBorrowMask,
        bytes32 _suppliedBorrowMask
    ) internal pure returns (bool) {
        bytes32 targetMask = _borrowedBorrowMask | (_suppliedBorrowMask << 1);
        return _userMarkets & targetMask == targetMask;
    }

    function setBorrowing(
        address _user,
        bytes32 _borrowMask,
        bool _borrowing
    ) internal {
        if (_borrowing) p().userMarkets[_user] |= _borrowMask;
        else p().userMarkets[_user] &= ~_borrowMask;
    }

    function setSupplying(
        address _user,
        bytes32 _borrowMask,
        bool _supplying
    ) internal {
        if (_supplying) p().userMarkets[_user] |= _borrowMask << 1;
        else p().userMarkets[_user] &= ~(_borrowMask << 1);
    }

    function getUserSupplyBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256)
    {
        Types.Balance memory userSupplyBalance = p().supplyBalanceInOf[_poolToken][_user];
        return
            userSupplyBalance.inP2P.rayMul(m().p2pSupplyIndex[_poolToken]) +
            userSupplyBalance.onPool.rayMul(m().poolIndexes[_poolToken].poolSupplyIndex);
    }

    function getUserBorrowBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256)
    {
        Types.Balance memory userBorrowBalance = p().borrowBalanceInOf[_poolToken][_user];
        return
            userBorrowBalance.inP2P.rayMul(m().p2pBorrowIndex[_poolToken]) +
            userBorrowBalance.onPool.rayMul(m().poolIndexes[_poolToken].poolBorrowIndex);
    }

    function collateralValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 value) {
        value = (getUserSupplyBalanceInOf(_poolToken, _user) * _underlyingPrice) / _tokenUnit;
    }

    function debtValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 value) {
        value = (getUserBorrowBalanceInOf(_poolToken, _user) * _underlyingPrice) / _tokenUnit;
    }

    function liquidityData(
        address _user,
        address _poolToken,
        uint256 _amountWithdrawn,
        uint256 _amountBorrowed
    ) internal view returns (Types.LiquidityData memory values) {
        IPriceOracleGetter oracle = IPriceOracleGetter(c().addressesProvider.getPriceOracle());
        Types.AssetLiquidityData memory assetData;
        Types.LiquidityStackVars memory vars;

        DataTypes.UserConfigurationMap memory morphoPoolConfig = c().pool.getUserConfiguration(
            address(this)
        );
        vars.poolTokensLength = m().marketsCreated.length;
        vars.userMarkets = p().userMarkets[_user];

        for (uint256 i; i < vars.poolTokensLength; ++i) {
            vars.poolToken = m().marketsCreated[i];
            vars.borrowMask = m().borrowMask[vars.poolToken];

            if (!isSupplyingOrBorrowing(vars.userMarkets, vars.borrowMask)) continue;

            vars.underlyingToken = m().market[vars.poolToken].underlyingToken;
            vars.underlyingPrice = oracle.getAssetPrice(vars.underlyingToken);

            if (vars.poolToken != _poolToken) LibIndexes.updateIndexes(vars.poolToken);

            (assetData.ltv, assetData.liquidationThreshold, , assetData.decimals, , ) = c()
            .pool
            .getConfiguration(vars.underlyingToken)
            .getParams();

            // LTV should be zero if Morpho has not enabled this asset as collateral
            if (
                !morphoPoolConfig.isUsingAsCollateral(
                    c().pool.getReserveData(vars.underlyingToken).id
                )
            ) assetData.ltv = 0;

            // If a LTV has been reduced to 0 on Aave v3, the other assets of the collateral are frozen.
            // In response, Morpho disables the asset as collateral and sets its liquidation threshold to 0.
            if (assetData.ltv == 0) assetData.liquidationThreshold = 0;

            unchecked {
                assetData.tokenUnit = 10**assetData.decimals;
            }

            if (isBorrowing(vars.userMarkets, vars.borrowMask)) {
                values.debt += debtValue(
                    vars.poolToken,
                    _user,
                    vars.underlyingPrice,
                    assetData.tokenUnit
                );
            }

            // Cache current asset collateral value.
            uint256 assetCollateralValue;
            if (isSupplying(vars.userMarkets, vars.borrowMask)) {
                assetCollateralValue = collateralValue(
                    vars.poolToken,
                    _user,
                    vars.underlyingPrice,
                    assetData.tokenUnit
                );
                values.collateral += assetCollateralValue;
                // Calculate LTV for borrow.
                values.maxDebt += assetCollateralValue.percentMul(assetData.ltv);
            }

            // Update debt variable for borrowed token.
            if (_poolToken == vars.poolToken && _amountBorrowed > 0)
                values.debt += (_amountBorrowed * vars.underlyingPrice).divUp(assetData.tokenUnit);

            // Update LT variable for withdraw.
            if (assetCollateralValue > 0)
                values.liquidationThreshold += assetCollateralValue.percentMul(
                    assetData.liquidationThreshold
                );

            // Subtract withdrawn amount from liquidation threshold and collateral.
            if (_poolToken == vars.poolToken && _amountWithdrawn > 0) {
                uint256 withdrawn = (_amountWithdrawn * vars.underlyingPrice) / assetData.tokenUnit;
                values.collateral -= withdrawn;
                values.liquidationThreshold -= withdrawn.percentMul(assetData.liquidationThreshold);
                values.maxDebt -= withdrawn.percentMul(assetData.ltv);
            }
        }
    }
}
