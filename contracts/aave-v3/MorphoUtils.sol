// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import "@aave/core-v3/contracts/interfaces/IAToken.sol";

import "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import "../common/libraries/DelegateCall.sol";

import "./MorphoStorage.sol";

/// @title MorphoUtils.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Modifiers, getters and other util functions for Morpho.
contract MorphoUtils is MorphoStorage {
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

    /// @notice Updates the peer-to-peer indexes and pool indexes (only stored locally).
    /// @param _poolTokenAddress The address of the market to update.
    function updateIndexes(address _poolTokenAddress) external isMarketCreated(_poolTokenAddress) {
        _updateIndexes(_poolTokenAddress);
    }

    /// INTERNAL ///

    /// @dev Returns if a user has been borrowing or supplying on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been using a reserve for borrowing or as collateral, false otherwise.
    function _isSupplyingOrBorrowing(address _user, address _market) internal view returns (bool) {
        unchecked {
            return (userMarketsBitmask[_user] >> (indexOfMarket[_market] << 1)) & 3 != 0;
        }
    }

    /// @dev Returns if a user is borrowing on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been borrowing on this market, false otherwise.
    function _isBorrowing(address _user, address _market) internal view returns (bool) {
        unchecked {
            return (userMarketsBitmask[_user] >> (indexOfMarket[_market] << 1)) & 1 != 0;
        }
    }

    /// @dev Returns if a user is supplying on a given market.
    /// @param _user The user to check for.
    /// @param _market The address of the market to check.
    /// @return True if the user has been supplying on this market, false otherwise.
    function _isSupplying(address _user, address _market) internal view returns (bool) {
        unchecked {
            return (userMarketsBitmask[_user] >> ((indexOfMarket[_market] << 1) + 1)) & 1 != 0;
        }
    }

    /// @dev Returns if a user has been borrowing from any market.
    /// @param _user The user to check for.
    /// @return True if the user has been borrowing on any market, false otherwise.
    function _isBorrowingAny(address _user) internal view returns (bool) {
        return userMarketsBitmask[_user] & BORROWING_MASK != 0;
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
        unchecked {
            uint256 bit = 1 << (indexOfMarket[_market] << 1);
            if (_borrowing) userMarketsBitmask[_user] |= bit;
            else userMarketsBitmask[_user] &= ~bit;
        }
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
        unchecked {
            uint256 bit = 1 << ((indexOfMarket[_market] << 1) + 1);
            if (_supplying) userMarketsBitmask[_user] |= bit;
            else userMarketsBitmask[_user] &= ~bit;
        }
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
}
