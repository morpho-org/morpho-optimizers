// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/CompoundMath.sol";
import "./libraries/DelegateCall.sol";

import "./MorphoStorage.sol";

/// @title MorphoUtils.
/// @notice Modifiers, getters and other util functions for Morpho.
abstract contract MorphoUtils is MorphoStorage {
    using DoubleLinkedList for DoubleLinkedList.List;
    using CompoundMath for uint256;
    using DelegateCall for address;

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
    function updateP2PIndexes(address _poolTokenAddress) public {
        address(interestRates).functionDelegateCall(
            abi.encodeWithSelector(interestRates.updateP2PIndexes.selector, _poolTokenAddress)
        );
    }

    /// INTERNAL ///

    /// @dev Checks whether the user has enough collateral to maintain such a borrow position.
    /// @param _user The user to check.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The amount of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    function _isLiquidable(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (bool) {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;

        uint256 maxDebtValue;
        uint256 debtValue;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];

            // Calling accrueInterest so that Compound's indexes used in _getUserLiquidityDataForAsset() are updated.
            ICToken(poolTokenEntered).accrueInterest();
            Types.AssetLiquidityData memory assetData = _getUserLiquidityDataForAsset(
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
        return debtValue > maxDebtValue;
    }

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function _getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        ICompoundOracle _oracle
    ) internal returns (Types.AssetLiquidityData memory assetData) {
        assetData.underlyingPrice = _oracle.getUnderlyingPrice(_poolTokenAddress);
        (, assetData.collateralFactor, ) = comptroller.markets(_poolTokenAddress);

        assetData.collateralValue = _getUserSupplyBalanceInOf(_poolTokenAddress, _user).mul(
            assetData.underlyingPrice
        );
        assetData.debtValue = _getUserBorrowBalanceInOf(_poolTokenAddress, _user).mul(
            assetData.underlyingPrice
        );
        assetData.maxDebtValue = assetData.collateralValue.mul(assetData.collateralFactor);
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the correct values.
    /// @param _poolTokenAddress The address of the market.
    /// @return updatedP2PSupplyIndex_ The updated peer-to-peer supply index.
    function _getUpdatedP2PSupplyIndex(address _poolTokenAddress)
        internal
        returns (uint256 updatedP2PSupplyIndex_)
    {
        return
            abi.decode(
                address(interestRates).functionDelegateCall(
                    abi.encodeWithSelector(
                        interestRates.getUpdatedP2PSupplyIndex.selector,
                        _poolTokenAddress
                    )
                ),
                (uint256)
            );
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the correct values.
    /// @param _poolTokenAddress The address of the market.
    /// @return updatedP2PBorrowIndex_ The updated peer-to-peer borrow index.
    function _getUpdatedP2PBorrowIndex(address _poolTokenAddress)
        internal
        returns (uint256 updatedP2PBorrowIndex_)
    {
        return
            abi.decode(
                address(interestRates).functionDelegateCall(
                    abi.encodeWithSelector(
                        interestRates.getUpdatedP2PBorrowIndex.selector,
                        _poolTokenAddress
                    )
                ),
                (uint256)
            );
    }

    /// @dev Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @dev Note: Compute the result with the index stored and not the most up to date one.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(address _poolTokenAddress, address _user)
        internal
        returns (uint256)
    {
        return
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P.mul(
                _getUpdatedP2PSupplyIndex(_poolTokenAddress)
            ) +
            supplyBalanceInOf[_poolTokenAddress][_user].onPool.mul(
                ICToken(_poolTokenAddress).exchangeRateStored()
            );
    }

    /// @dev Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(address _poolTokenAddress, address _user)
        internal
        returns (uint256)
    {
        return
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P.mul(
                _getUpdatedP2PBorrowIndex(_poolTokenAddress)
            ) +
            borrowBalanceInOf[_poolTokenAddress][_user].onPool.mul(
                ICToken(_poolTokenAddress).borrowIndex()
            );
    }

    /// @dev Returns the underlying ERC20 token related to the pool token.
    /// @param _poolTokenAddress The address of the pool token.
    /// @return The underlying ERC20 token.
    function _getUnderlying(address _poolTokenAddress) internal view returns (ERC20) {
        if (_poolTokenAddress == cEth)
            // cETH has no underlying() function.
            return ERC20(wEth);
        else return ERC20(ICToken(_poolTokenAddress).underlying());
    }
}
