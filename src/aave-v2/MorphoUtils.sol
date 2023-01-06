// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./interfaces/aave/IPriceOracleGetter.sol";
import "./interfaces/aave/IAToken.sol";

import "./libraries/aave/ReserveConfiguration.sol";

import "@morpho-dao/morpho-utils/DelegateCall.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";

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
    using Math for uint256;

    /// ERRORS ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct LiquidityVars {
        address poolToken;
        uint256 poolTokensLength;
        bytes32 userMarkets;
        bytes32 borrowMask;
        address underlyingToken;
        uint256 underlyingPrice;
    }

    /// MODIFIERS ///

    /// @notice Prevents to update a market not created yet.
    /// @param _poolToken The address of the market to check.
    modifier isMarketCreated(address _poolToken) {
        if (!market[_poolToken].isCreated) revert MarketNotCreated();
        _;
    }

    /// EXTERNAL ///

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market addresses.
    function getMarketsCreated() external view returns (address[] memory) {
        return marketsCreated;
    }

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolToken The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolToken, Types.PositionType _positionType)
        external
        view
        returns (address head)
    {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            head = suppliersInP2P[_poolToken].getHead();
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            head = suppliersOnPool[_poolToken].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            head = borrowersInP2P[_poolToken].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            head = borrowersOnPool[_poolToken].getHead();
    }

    /// @notice Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @dev Beware that this function does not give the account with the highest liquidity.
    /// @param _poolToken The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolToken,
        Types.PositionType _positionType,
        address _user
    ) external view returns (address next) {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            next = suppliersInP2P[_poolToken].getNext(_user);
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            next = suppliersOnPool[_poolToken].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            next = borrowersInP2P[_poolToken].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            next = borrowersOnPool[_poolToken].getNext(_user);
    }

    /// @notice Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolToken The address of the market to update.
    function updateIndexes(address _poolToken) external isMarketCreated(_poolToken) {
        _updateIndexes(_poolToken);
    }

    /// INTERNAL ///

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isSupplyingOrBorrowing(bytes32 _userMarkets, bytes32 _borrowMask)
        internal
        pure
        returns (bool)
    {
        return _userMarkets & (_borrowMask | (_borrowMask << 1)) != 0;
    }

    /// @dev Returns if a user is borrowing on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been borrowing on this market, false otherwise.
    function _isBorrowing(bytes32 _userMarkets, bytes32 _borrowMask) internal pure returns (bool) {
        return _userMarkets & _borrowMask != 0;
    }

    /// @dev Returns if a user is supplying on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying on this market, false otherwise.
    function _isSupplying(bytes32 _userMarkets, bytes32 _borrowMask) internal pure returns (bool) {
        return _userMarkets & (_borrowMask << 1) != 0;
    }

    /// @dev Returns if a user has been borrowing from any market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @return True if the user has been borrowing on any market, false otherwise.
    function _isBorrowingAny(bytes32 _userMarkets) internal pure returns (bool) {
        return _userMarkets & BORROWING_MASK != 0;
    }

    /// @dev Returns if a user is borrowing on a given market and supplying on another given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowedBorrowMask The borrow mask of the market to check whether the user is borrowing.
    /// @param _suppliedBorrowMask The borrow mask of the market to check whether the user is supplying.
    /// @return True if the user is borrowing on the given market and supplying on the other given market, false otherwise.
    function _isBorrowingAndSupplying(
        bytes32 _userMarkets,
        bytes32 _borrowedBorrowMask,
        bytes32 _suppliedBorrowMask
    ) internal pure returns (bool) {
        bytes32 targetMask = _borrowedBorrowMask | (_suppliedBorrowMask << 1);
        return _userMarkets & targetMask == targetMask;
    }

    /// @notice Sets if the user is borrowing on a market.
    /// @param _user The user to set for.
    /// @param _borrowMask The borrow mask of the market to mark as borrowed.
    /// @param _borrowing True if the user is borrowing, false otherwise.
    function _setBorrowing(
        address _user,
        bytes32 _borrowMask,
        bool _borrowing
    ) internal {
        if (_borrowing) userMarkets[_user] |= _borrowMask;
        else userMarkets[_user] &= ~_borrowMask;
    }

    /// @notice Sets if the user is supplying on a market.
    /// @param _user The user to set for.
    /// @param _borrowMask The borrow mask of the market to mark as supplied.
    /// @param _supplying True if the user is supplying, false otherwise.
    function _setSupplying(
        address _user,
        bytes32 _borrowMask,
        bool _supplying
    ) internal {
        if (_supplying) userMarkets[_user] |= _borrowMask << 1;
        else userMarkets[_user] &= ~(_borrowMask << 1);
    }

    /// @dev Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolToken The address of the market to update.
    function _updateIndexes(address _poolToken) internal {
        address(interestRatesManager).functionDelegateCall(
            abi.encodeWithSelector(interestRatesManager.updateIndexes.selector, _poolToken)
        );
    }

    /// @dev Returns the supply balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param _user The address of the user.
    /// @param _poolToken The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256)
    {
        Types.SupplyBalance memory userSupplyBalance = supplyBalanceInOf[_poolToken][_user];
        return
            userSupplyBalance.inP2P.rayMul(p2pSupplyIndex[_poolToken]) +
            userSupplyBalance.onPool.rayMul(poolIndexes[_poolToken].poolSupplyIndex);
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolToken` market.
    /// @dev Note: Computes the result with the stored indexes, which are not always the most up to date ones.
    /// @param _user The address of the user.
    /// @param _poolToken The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(address _poolToken, address _user)
        internal
        view
        returns (uint256)
    {
        Types.BorrowBalance memory userBorrowBalance = borrowBalanceInOf[_poolToken][_user];
        return
            userBorrowBalance.inP2P.rayMul(p2pBorrowIndex[_poolToken]) +
            userBorrowBalance.onPool.rayMul(poolIndexes[_poolToken].poolBorrowIndex);
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
    ) internal view returns (uint256 collateral) {
        collateral = (_getUserSupplyBalanceInOf(_poolToken, _user) * _underlyingPrice) / _tokenUnit;
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
    ) internal view returns (uint256 debt) {
        debt = (_getUserBorrowBalanceInOf(_poolToken, _user) * _underlyingPrice).divUp(_tokenUnit);
    }

    /// @dev Calculates the total value of the collateral, debt, and LTV/LT value depending on the calculation type.
    /// @dev Expects the given user's entered markets to include the given market.
    /// @dev Expects the given market's pool & peer-to-peer indexes to have been updated.
    /// @dev Expects `_amountWithdrawn` to be less than or equal to the given user's supply on the given market.
    /// @param _user The user address.
    /// @param _poolToken The pool token that is being borrowed or withdrawn.
    /// @param _amountWithdrawn The amount that is being withdrawn.
    /// @param _amountBorrowed The amount that is being borrowed.
    /// @return values The struct containing health factor, collateral, debt, ltv, liquidation threshold values.
    function _liquidityData(
        address _user,
        address _poolToken,
        uint256 _amountWithdrawn,
        uint256 _amountBorrowed
    ) internal returns (Types.LiquidityData memory values) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        Types.AssetLiquidityData memory assetData;
        LiquidityVars memory vars;

        vars.poolTokensLength = marketsCreated.length;
        vars.userMarkets = userMarkets[_user];

        for (uint256 i; i < vars.poolTokensLength; ++i) {
            vars.poolToken = marketsCreated[i];
            vars.borrowMask = borrowMask[vars.poolToken];

            if (!_isSupplyingOrBorrowing(vars.userMarkets, vars.borrowMask)) continue;

            vars.underlyingToken = market[vars.poolToken].underlyingToken;
            vars.underlyingPrice = oracle.getAssetPrice(vars.underlyingToken);

            if (vars.poolToken != _poolToken) _updateIndexes(vars.poolToken);

            // Assumes that the Morpho contract has not disabled the asset as collateral in the underlying pool.
            (assetData.ltv, assetData.liquidationThreshold, , assetData.decimals, ) = pool
            .getConfiguration(vars.underlyingToken)
            .getParamsMemory();

            unchecked {
                assetData.tokenUnit = 10**assetData.decimals;
            }

            if (_isBorrowing(vars.userMarkets, vars.borrowMask)) {
                values.debtEth += _debtValue(
                    vars.poolToken,
                    _user,
                    vars.underlyingPrice,
                    assetData.tokenUnit
                );
            }

            // Cache current asset collateral value.
            if (_isSupplying(vars.userMarkets, vars.borrowMask)) {
                uint256 assetCollateralEth = _collateralValue(
                    vars.poolToken,
                    _user,
                    vars.underlyingPrice,
                    assetData.tokenUnit
                );
                values.collateralEth += assetCollateralEth;
                // Calculate LTV for borrow.
                values.borrowableEth += assetCollateralEth.percentMul(assetData.ltv);

                // Update LT variable for withdraw.
                if (assetCollateralEth > 0)
                    values.maxDebtEth += assetCollateralEth.percentMul(
                        assetData.liquidationThreshold
                    );
            }

            // Update debt variable for borrowed token.
            if (_poolToken == vars.poolToken && _amountBorrowed > 0)
                values.debtEth += (_amountBorrowed * vars.underlyingPrice).divUp(
                    assetData.tokenUnit
                );

            // Subtract withdrawn amount from liquidation threshold and collateral.
            if (_poolToken == vars.poolToken && _amountWithdrawn > 0) {
                uint256 withdrawn = (_amountWithdrawn * vars.underlyingPrice) / assetData.tokenUnit;
                values.collateralEth -= withdrawn;
                values.maxDebtEth -= withdrawn.percentMul(assetData.liquidationThreshold);
                values.borrowableEth -= withdrawn.percentMul(assetData.ltv);
            }
        }
    }
}
