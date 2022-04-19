// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IWETH.sol";

import {LibStorage, MarketsStorage, PositionsStorage} from "./LibStorage.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../../common/libraries/DoubleLinkedList.sol";
import "./LibMarketsManager.sol";
import "./CompoundMath.sol";
import "./Types.sol";

library LibPositionsManagerGetters {
    using DoubleLinkedList for DoubleLinkedList.List;
    using CompoundMath for uint256;

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolTokenAddress, Types.PositionType _positionType)
        internal
        view
        returns (address head)
    {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            head = ps().suppliersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            head = ps().suppliersOnPool[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            head = ps().borrowersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            head = ps().borrowersOnPool[_poolTokenAddress].getHead();
    }

    /// @notice Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolTokenAddress,
        Types.PositionType _positionType,
        address _user
    ) internal view returns (address next) {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            next = ps().suppliersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            next = ps().suppliersOnPool[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            next = ps().borrowersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            next = ps().borrowersOnPool[_poolTokenAddress].getNext(_user);
    }

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine liquidity for.
    /// @return collateralValue The collateral value of the user.
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum possible debt value of the user.
    function getUserBalanceStates(address _user)
        internal
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        ICompoundOracle oracle = ICompoundOracle(ms().comptroller.oracle());
        uint256 numberOfEnteredMarkets = ps().enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = ps().enteredMarkets[_user][i];
            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            unchecked {
                collateralValue += assetData.collateralValue;
                maxDebtValue += assetData.maxDebtValue;
                debtValue += assetData.debtValue;
                ++i;
            }
        }
    }

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine the capacities for.
    /// @param _poolTokenAddress The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        internal
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        Types.LiquidityData memory data;
        Types.AssetLiquidityData memory assetData;
        ICompoundOracle oracle = ICompoundOracle(ms().comptroller.oracle());
        uint256 numberOfEnteredMarkets = ps().enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = ps().enteredMarkets[_user][i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, oracle);

                unchecked {
                    data.maxDebtValue += assetData.maxDebtValue;
                    data.debtValue += assetData.debtValue;
                }
            }

            unchecked {
                ++i;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        unchecked {
            data.maxDebtValue += assetData.maxDebtValue;
            data.debtValue += assetData.debtValue;
        }

        // Not possible to withdraw nor borrow.
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        uint256 differenceInUnderlying = (data.maxDebtValue - data.debtValue).div(
            assetData.underlyingPrice
        );

        withdrawable = assetData.collateralValue.div(assetData.underlyingPrice);
        if (assetData.collateralFactor != 0) {
            withdrawable = Math.min(
                withdrawable,
                differenceInUnderlying.div(assetData.collateralFactor)
            );
        }

        borrowable = differenceInUnderlying;
    }

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        ICompoundOracle _oracle
    ) public view returns (Types.AssetLiquidityData memory assetData) {
        assetData.underlyingPrice = _oracle.getUnderlyingPrice(_poolTokenAddress);
        (, assetData.collateralFactor, ) = ms().comptroller.markets(_poolTokenAddress);

        assetData.collateralValue = getUserSupplyBalanceInOf(_poolTokenAddress, _user).mul(
            assetData.underlyingPrice
        );
        assetData.debtValue = getUserBorrowBalanceInOf(_poolTokenAddress, _user).mul(
            assetData.underlyingPrice
        );
        assetData.maxDebtValue = assetData.collateralValue.mul(assetData.collateralFactor);
    }

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum debt value possible of the user.
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (uint256 debtValue, uint256 maxDebtValue) {
        ICompoundOracle oracle = ICompoundOracle(ms().comptroller.oracle());
        uint256 numberOfEnteredMarkets = ps().enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = ps().enteredMarkets[_user][i];

            // Calling accrueInterest so that computation in getUserLiquidityDataForAsset() are the most accurate ones.
            ICToken(poolTokenEntered).accrueInterest();
            Types.AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            unchecked {
                maxDebtValue += assetData.maxDebtValue;
                debtValue += assetData.debtValue;
                ++i;
            }

            if (_poolTokenAddress == poolTokenEntered) {
                debtValue += _borrowedAmount.mul(assetData.underlyingPrice);
                uint256 maxDebtValueSub = _withdrawnAmount.mul(assetData.underlyingPrice).mul(
                    assetData.collateralFactor
                );

                unchecked {
                    maxDebtValue -= maxDebtValue < maxDebtValueSub ? maxDebtValue : maxDebtValueSub;
                }
            }
        }
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @dev Note: compute the result with the exchange rate stored and not the most up to date.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function getUserSupplyBalanceInOf(address _poolTokenAddress, address _user)
        internal
        view
        returns (uint256)
    {
        (uint256 supplyP2PExchangeRate, ) = LibMarketsManager.getUpdatedP2PExchangeRates(
            _poolTokenAddress
        );

        return
            ps().supplyBalanceInOf[_poolTokenAddress][_user].inP2P.mul(supplyP2PExchangeRate) +
            ps().supplyBalanceInOf[_poolTokenAddress][_user].onPool.mul(
                ICToken(_poolTokenAddress).exchangeRateStored()
            );
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function getUserBorrowBalanceInOf(address _poolTokenAddress, address _user)
        internal
        view
        returns (uint256)
    {
        (, uint256 borrowP2PExchangeRate) = LibMarketsManager.getUpdatedP2PExchangeRates(
            _poolTokenAddress
        );

        return
            ps().borrowBalanceInOf[_poolTokenAddress][_user].inP2P.mul(borrowP2PExchangeRate) +
            ps().borrowBalanceInOf[_poolTokenAddress][_user].onPool.mul(
                ICToken(_poolTokenAddress).borrowIndex()
            );
    }

    /// @dev Returns the underlying ERC20 token related to the pool token.
    /// @param _poolTokenAddress The address of the pool token.
    /// @return The underlying ERC20 token.
    function getUnderlying(address _poolTokenAddress) internal view returns (ERC20) {
        if (_poolTokenAddress == ps().cEth)
            // cETH has no underlying() function.
            return ERC20(ps().wEth);
        else return ERC20(ICToken(_poolTokenAddress).underlying());
    }
}
