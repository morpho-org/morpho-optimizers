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

    /// INTERNAL ///

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying or borrowing on this market, false otherwise.
    function _isSupplyingOrBorrowing(uint256 _userMarkets, uint256 _borrowMask)
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
    function _isBorrowing(uint256 _userMarkets, uint256 _borrowMask) internal pure returns (bool) {
        return _userMarkets & _borrowMask != 0;
    }

    /// @dev Returns if a user is supplying on a given market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @param _borrowMask The borrow mask of the market to check.
    /// @return True if the user has been supplying on this market, false otherwise.
    function _isSupplying(uint256 _userMarkets, uint256 _borrowMask) internal pure returns (bool) {
        return _userMarkets & (_borrowMask << 1) != 0;
    }

    /// @dev Returns if a user has been borrowing from any market.
    /// @param _userMarkets The bitmask encoding the markets entered by the user.
    /// @return True if the user has been borrowing on any market, false otherwise.
    function _isBorrowingAny(uint256 _userMarkets) internal pure returns (bool) {
        return _userMarkets & BORROWING_MASK != 0;
    }

    /// @notice Sets if the user is borrowing on a market.
    /// @param _user The user to set for.
    /// @param _borrowMask The borrow mask of the market to mark as borrowed.
    /// @param _borrowing True if the user is borrowing, false otherwise.
    function _setBorrowing(
        address _user,
        uint256 _borrowMask,
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
        uint256 _borrowMask,
        bool _supplying
    ) internal {
        if (_supplying) userMarkets[_user] |= _borrowMask << 1;
        else userMarkets[_user] &= ~(_borrowMask << 1);
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
        Types.SupplyBalance memory userSupplyBalance = supplyBalanceInOf[_poolTokenAddress][_user];
        return
            userSupplyBalance.inP2P.rayMul(p2pSupplyIndex[_poolTokenAddress]) +
            userSupplyBalance.onPool.rayMul(poolIndexes[_poolTokenAddress].poolSupplyIndex);
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
        Types.BorrowBalance memory userBorrowBalance = borrowBalanceInOf[_poolTokenAddress][_user];
        return
            userBorrowBalance.inP2P.rayMul(p2pBorrowIndex[_poolTokenAddress]) +
            userBorrowBalance.onPool.rayMul(poolIndexes[_poolTokenAddress].poolBorrowIndex);
    }
}
