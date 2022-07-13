// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/aave/IPriceOracleGetter.sol";
import "./interfaces/aave/IAToken.sol";

import "./libraries/aave/ReserveConfiguration.sol";
import "../common/libraries/DelegateCall.sol";
import "./libraries/aave/PercentageMath.sol";
import "./libraries/aave/WadRayMath.sol";

import "./MorphoStorage.sol";

/// @title MorphoUtils.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Modifiers, getters and other util functions for Morpho.
abstract contract MorphoUtils is MorphoStorage {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using PercentageMath for uint256;
    using DelegateCall for address;
    using WadRayMath for uint256;

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
        Types.MarketStatus memory marketStatus = marketStatus[_poolTokenAddress];
        if (!marketStatus.isCreated) revert MarketNotCreated();
        if (marketStatus.isPaused) revert MarketPaused();
        _;
    }

    /// @notice Prevents a user to trigger a function when market is not created or paused or partial paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPausedNorPartiallyPaused(address _poolTokenAddress) {
        Types.MarketStatus memory marketStatus = marketStatus[_poolTokenAddress];
        if (!marketStatus.isCreated) revert MarketNotCreated();
        if (marketStatus.isPaused || marketStatus.isPartiallyPaused) revert MarketPaused();
        _;
    }

    /// EXTERNAL ///

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market addresses.
    function getMarketsCreated() external view returns (address[] memory) {
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
        else head = borrowersOnPool[_poolTokenAddress].getHead();
        // Borrowers on pool.
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
        else next = borrowersOnPool[_poolTokenAddress].getNext(_user);
        // Borrowers on pool.
    }

    /// @notice Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolTokenAddress The address of the market to update.
    function updateIndexes(address _poolTokenAddress) external isMarketCreated(_poolTokenAddress) {
        _updateIndexes(_poolTokenAddress);
    }

    /// @notice Returns collateral, debt, loan to value, and liquidation thresholds for a user.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The address of the market to borrow or withdraw from (can be zero).
    /// @param _withdrawnAmount The amount hypothetically withdrawn from the market.
    /// @param _borrowedAmount The amount hypothetically borrowed from the market.
    /// @return The collateral, debt, loan to value, and liquidation thresholds for a user.
    function getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) external view returns (Types.LiquidityData memory) {
        return
            _liquidityData(
                _user,
                _userMarkets(_user),
                _poolTokenAddress,
                _withdrawnAmount,
                _borrowedAmount
            );
    }

    /// INTERNAL ///

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isSupplyingOrBorrowing(address _user, address _market) internal view returns (bool) {
        uint256 bmask = borrowMask[_market];
        return userMarkets[_user] & (bmask | (bmask << 1)) != 0;
    }

    /// @dev Returns if a user is borrowing on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been borrowing on this market, false otherwise.
    function _isBorrowing(address _user, address _market) internal view returns (bool) {
        return userMarkets[_user] & borrowMask[_market] != 0;
    }

    /// @dev Returns if a user is supplying on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been supplying on this market, false otherwise.
    function _isSupplying(address _user, address _market) internal view returns (bool) {
        return userMarkets[_user] & (borrowMask[_market] << 1) != 0;
    }

    /// @dev Returns if a user has been borrowing from any market.
    /// @param _user The user to check for.
    /// @return True if the user has been borrowing on any market, false otherwise.
    function _isBorrowingAny(address _user) internal view returns (bool) {
        return userMarkets[_user] & BORROWING_MASK != 0;
    }

    /// @notice Sets if the user is borrowing on a market.
    /// @param _user The user to set for.
    /// @param _market The address of the market to mark as borrowed.
    /// @param _borrowing True if the user is borrowing, false otherwise.
    function _setBorrowing(
        address _user,
        address _market,
        bool _borrowing
    ) internal {
        if (_borrowing) userMarkets[_user] |= borrowMask[_market];
        else userMarkets[_user] &= ~borrowMask[_market];
    }

    /// @notice Sets if the user is supplying on a market.
    /// @param _user The user to set for.
    /// @param _market The address of the market to mark as supplied.
    /// @param _supplying True if the user is supplying, false otherwise.
    function _setSupplying(
        address _user,
        address _market,
        bool _supplying
    ) internal {
        if (_supplying) userMarkets[_user] |= borrowMask[_market] << 1;
        else userMarkets[_user] &= ~(borrowMask[_market] << 1);
    }

    /// @dev Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolTokenAddress The address of the market to update.
    function _updateIndexes(address _poolTokenAddress) internal {
        address(interestRatesManager).functionDelegateCall(
            abi.encodeWithSelector(interestRatesManager.updateIndexes.selector, _poolTokenAddress)
        );
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
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
                poolIndexes[_poolTokenAddress].poolSupplyIndex
            );
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
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
                poolIndexes[_poolTokenAddress].poolBorrowIndex
            );
    }

    /// @dev Gets all markets of the user.
    /// @param _user The user address.
    /// @return markets The markets the user is participating in.
    function _userMarkets(address _user) internal view returns (address[] memory markets) {
        uint256 marketsCreatedLength = marketsCreated.length;
        uint256 marketLength;
        markets = new address[](marketsCreatedLength);

        unchecked {
            for (uint256 i; i < marketsCreatedLength; ++i) {
                if (_isSupplyingOrBorrowing(_user, marketsCreated[i])) {
                    markets[marketLength] = marketsCreated[i];
                    ++marketLength;
                }
            }
        }

        // Resize the array for return.
        assembly {
            mstore(markets, marketLength)
        }
    }

    /// @dev Calculates the total value of the collateral, debt, and LTV/LT value depending on the calculation type.
    /// @param _user The user address.
    /// @param _poolTokens The pool tokens to calculate the values for.
    /// @param _poolTokenAddress The pool token that is being borrowed or withdrawn.
    /// @param _amountWithdrawn The amount that is being withdrawn.
    /// @param _amountBorrowed The amount that is being borrowed.
    /// @return values The struct containing health factor, collateral, debt, ltv, liquidation threshold values.
    function _liquidityData(
        address _user,
        address[] memory _poolTokens,
        address _poolTokenAddress,
        uint256 _amountWithdrawn,
        uint256 _amountBorrowed
    ) internal view returns (Types.LiquidityData memory values) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        Types.AssetLiquidityData memory assetData;

        for (uint256 i; i < _poolTokens.length; ) {
            address underlyingAddress = IAToken(_poolTokens[i]).UNDERLYING_ASSET_ADDRESS();
            uint256 underlyingPrice = oracle.getAssetPrice(underlyingAddress);

            (assetData.ltv, assetData.liquidationThreshold, , assetData.reserveDecimals, ) = pool
            .getConfiguration(underlyingAddress)
            .getParamsMemory();

            unchecked {
                assetData.tokenUnit = 10**assetData.reserveDecimals; // Cannot overflow.
            }

            if (_isBorrowing(_user, _poolTokens[i])) {
                values.debtValue += _debtValue(
                    _poolTokens[i],
                    _user,
                    underlyingPrice,
                    assetData.tokenUnit
                );
            }

            // Cache current asset collateral value
            uint256 assetCollateralValue;
            if (_isSupplying(_user, _poolTokens[i])) {
                assetCollateralValue = _collateralValue(
                    _poolTokens[i],
                    _user,
                    underlyingPrice,
                    assetData.tokenUnit
                );
                values.collateralValue += assetCollateralValue;
            }

            // Calculate LTV for borrow.
            values.maxLoanToValue += assetCollateralValue.percentMul(assetData.ltv);
            // Add debt value for borrowed token.
            if (_poolTokenAddress == _poolTokens[i] && _amountBorrowed > 0)
                values.debtValue += (_amountBorrowed * underlyingPrice) / assetData.tokenUnit;

            // Calculate LT for withdraw.
            if (assetCollateralValue > 0)
                values.liquidationThresholdValue += assetCollateralValue.percentMul(
                    assetData.liquidationThreshold
                );

            // Subtract from liquidation threshold value and collateral value for withdrawn token.
            if (_poolTokenAddress == _poolTokens[i] && _amountWithdrawn > 0) {
                values.collateralValue -=
                    (_amountWithdrawn * underlyingPrice) /
                    assetData.tokenUnit;
                values.liquidationThresholdValue -= ((_amountWithdrawn * underlyingPrice) /
                    assetData.tokenUnit)
                .percentMul(assetData.liquidationThreshold);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Calculates the value of the collateral.
    /// @param _poolToken The pool token to calculate the value for.
    /// @param _user The user address.
    /// @param _underlyingPrice The underlying price.
    /// @param _tokenUnit The token unit.
    function _collateralValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 collateralValue) {
        collateralValue =
            (_getUserSupplyBalanceInOf(_poolToken, _user) * _underlyingPrice) /
            _tokenUnit;
    }

    /// @dev Calculates the value of the debt.
    /// @param _poolToken The pool token to calculate the value for.
    /// @param _user The user address.
    /// @param _underlyingPrice The underlying price.
    /// @param _tokenUnit The token unit.
    function _debtValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 debtValue) {
        debtValue = (_getUserBorrowBalanceInOf(_poolToken, _user) * _underlyingPrice) / _tokenUnit;
    }
}
