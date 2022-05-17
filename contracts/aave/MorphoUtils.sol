// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/aave/IPriceOracleGetter.sol";
import "./interfaces/aave/IAToken.sol";

import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "../common/libraries/DelegateCall.sol";
import "./libraries/aave/PercentageMath.sol";
import "./libraries/Math.sol";

import "./MorphoStorage.sol";

/// @title MorphoUtils.
/// @notice Modifiers, getters and other util functions for Morpho.
contract MorphoUtils is MorphoStorage {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using DoubleLinkedList for DoubleLinkedList.List;
    using PercentageMath for uint256;
    using DelegateCall for address;
    using Math for uint256;

    /// ERRORS ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is paused.
    error MarketPaused();

    /// MODIFIERS ///

    /// @notice Prevents to update a market not created yet.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreated(address _poolTokenAddress) {
        if (!marketStatus[_poolTokenAddress].isCreated) revert MarketNotCreated();
        _;
    }

    /// @notice Prevents a user to trigger a function when market is not created or paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPaused(address _poolTokenAddress) {
        Types.MarketStatus memory marketStatus_ = marketStatus[_poolTokenAddress];
        if (!marketStatus_.isCreated) revert MarketNotCreated();
        if (marketStatus_.isPaused) revert MarketPaused();
        _;
    }

    /// @notice Prevents a user to trigger a function when market is not created or paused or partial paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolTokenAddress) {
        Types.MarketStatus memory marketStatus_ = marketStatus[_poolTokenAddress];
        if (!marketStatus_.isCreated) revert MarketNotCreated();
        if (marketStatus_.isPaused || marketStatus_.isPartiallyPaused) revert MarketPaused();
        _;
    }

    /// EXTERNAL ///

    /// @notice Returns all markets entered by a given user.
    /// @param _user The address of the user.
    /// @return enteredMarkets_ The list of markets entered by this user.
    function getEnteredMarkets(address _user)
        external
        view
        returns (address[] memory enteredMarkets_)
    {
        return enteredMarkets[_user];
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market addresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated_) {
        return marketsCreated;
    }

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolTokenAddress, Types.PositionType _positionType)
        external
        view
        returns (address head)
    {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            head = suppliersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            head = suppliersOnPool[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            head = borrowersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            head = borrowersOnPool[_poolTokenAddress].getHead();
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
    ) external view returns (address next) {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            next = suppliersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            next = suppliersOnPool[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            next = borrowersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            next = borrowersOnPool[_poolTokenAddress].getNext(_user);
    }

    /// PUBLIC ///

    /// @notice Updates the peer-to-peer indexes.
    /// @dev Note: This function updates the exchange rate on Compound. As a consequence only a call to exchangeRatesStored() is necessary to get the most up to date exchange rate.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PIndexes(address _poolTokenAddress) public isMarketCreated(_poolTokenAddress) {
        address(interestRatesManager).functionDelegateCall(
            abi.encodeWithSelector(
                interestRatesManager.updateP2PIndexes.selector,
                _poolTokenAddress
            )
        );
    }

    /// INTERNAL ///

    /// @dev Returns the debt value, max debt value and liquidation value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return liquidityData The hypothetical liquidity data of the user.
    function _getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (Types.LiquidityData memory liquidityData) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;
        uint256 i;

        Types.AssetLiquidityData memory assetData;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];
            unchecked {
                ++i;
            }

            updateP2PIndexes(poolTokenEntered);

            address underlyingAddress = IAToken(poolTokenEntered).UNDERLYING_ASSET_ADDRESS();
            assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH.
            (
                assetData.ltv,
                assetData.liquidationThreshold,
                ,
                assetData.reserveDecimals,

            ) = lendingPool.getConfiguration(underlyingAddress).getParamsMemory();

            assetData.tokenUnit = 10**assetData.reserveDecimals;
            assetData.debtValue =
                (_getUserBorrowBalanceInOf(poolTokenEntered, _user) * assetData.underlyingPrice) /
                assetData.tokenUnit;
            assetData.collateralValue =
                (_getUserSupplyBalanceInOf(poolTokenEntered, _user) * assetData.underlyingPrice) /
                assetData.tokenUnit;

            liquidityData.debtValue += assetData.debtValue;
            liquidityData.collateralValue += assetData.collateralValue;
            liquidityData.avgLtv += assetData.collateralValue * assetData.ltv;
            liquidityData.avgLiquidationThreshold +=
                assetData.collateralValue *
                assetData.liquidationThreshold;

            if (_poolTokenAddress == poolTokenEntered) {
                if (_borrowedAmount > 0)
                    liquidityData.debtValue +=
                        (_borrowedAmount * assetData.underlyingPrice) /
                        assetData.tokenUnit;

                if (_withdrawnAmount > 0) {
                    liquidityData.collateralValue -= Math.min(
                        (_withdrawnAmount * assetData.underlyingPrice) / assetData.tokenUnit,
                        liquidityData.collateralValue
                    );
                    liquidityData.avgLtv -= Math.min(
                        (_withdrawnAmount * assetData.underlyingPrice * assetData.ltv) /
                            assetData.tokenUnit,
                        liquidityData.avgLtv
                    );
                    liquidityData.avgLiquidationThreshold -= Math.min(
                        (_withdrawnAmount *
                            assetData.underlyingPrice *
                            assetData.liquidationThreshold) / assetData.tokenUnit,
                        liquidityData.avgLiquidationThreshold
                    );
                }
            }
        }

        if (liquidityData.collateralValue > 0) {
            liquidityData.avgLtv = liquidityData.avgLtv / liquidityData.collateralValue;
            liquidityData.avgLiquidationThreshold =
                liquidityData.avgLiquidationThreshold /
                liquidityData.collateralValue;
        } else {
            liquidityData.avgLtv = 0;
            liquidityData.avgLiquidationThreshold = 0;
        }

        liquidityData.healthFactor = liquidityData.debtValue == 0
            ? type(uint256).max
            : (liquidityData.collateralValue.percentMul(liquidityData.avgLiquidationThreshold))
            .wadDiv(liquidityData.debtValue);
    }

    /// @dev Checks whether the user can borrow or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return Whether the borrow is allowed or not.
    function _borrowAllowed(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (bool) {
        Types.LiquidityData memory liquidityData = _getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );

        return
            liquidityData.debtValue <=
            liquidityData.collateralValue.percentMul(liquidityData.avgLtv);
    }

    /// @dev Checks whether the user can withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return Whether the withdraw is allowed or not.
    function _withdrawAllowed(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (bool) {
        Types.LiquidityData memory liquidityData = _getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );

        return liquidityData.healthFactor > HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /// @dev Checks if the user is liquidable.
    /// @param _user The user to check.
    /// @return Whether the user is liquidable or not.
    function _liquidationAllowed(address _user) internal returns (bool) {
        Types.LiquidityData memory liquidityData = _getUserHypotheticalBalanceStates(
            _user,
            address(0),
            0,
            0
        );

        return liquidityData.healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(address _poolTokenAddress, address _user)
        internal
        view
        returns (uint256)
    {
        return
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P.rayMul(
                p2pSupplyIndex[_poolTokenAddress]
            ) +
            supplyBalanceInOf[_poolTokenAddress][_user].onPool.rayMul(
                lendingPool.getReserveNormalizedIncome(
                    IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
                )
            );
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(address _poolTokenAddress, address _user)
        internal
        view
        returns (uint256)
    {
        return
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P.rayMul(
                p2pBorrowIndex[_poolTokenAddress]
            ) +
            borrowBalanceInOf[_poolTokenAddress][_user].onPool.rayMul(
                lendingPool.getReserveNormalizedVariableDebt(
                    IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
                )
            );
    }
}
