// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./PositionsManagerForCompoundEventsErrors.sol";

/// @title PositionsManagerForCompoundGettersSetters.
/// @notice Getters and setters for PositionsManagerForCompound, including externals, internals, user-accessible and admin-only functions.
abstract contract PositionsManagerForCompoundGettersSetters is
    PositionsManagerForCompoundEventsErrors
{
    using DoubleLinkedList for DoubleLinkedList.List;
    using CompoundMath for uint256;

    /// MODIFIERS ///

    /// @notice Prevents a user to trigger a function when market is not created or paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPaused(address _poolTokenAddress) {
        if (!marketsManager.isCreated(_poolTokenAddress)) revert MarketNotCreated();
        if (paused[_poolTokenAddress]) revert MarketPaused();
        _;
    }

    /// @notice Prevents a user to call function only allowed for the markets manager.
    modifier onlyMarketsManager() {
        if (msg.sender != address(marketsManager)) revert OnlyMarketsManager();
        _;
    }

    /// SETTERS ///

    /// @notice Sets `NDS`.
    /// @param _newNDS The new `NDS` value.
    function setNDS(uint8 _newNDS) external onlyOwner {
        NDS = _newNDS;
        emit NDSSet(_newNDS);
    }

    /// @notice Sets `maxGas`.
    /// @param _maxGas The new `maxGas`.
    function setMaxGas(MaxGas memory _maxGas) external onlyOwner {
        maxGas = _maxGas;
        emit MaxGasSet(_maxGas);
    }

    /// @notice Sets the `treasuryVault`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyOwner {
        treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _newIncentivesVault The address of the new `incentivesVault`.
    function setIncentivesVault(address _newIncentivesVault) external onlyOwner {
        incentivesVault = IIncentivesVault(_newIncentivesVault);
        emit IncentivesVaultSet(_newIncentivesVault);
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyOwner {
        rewardsManager = IRewardsManagerForCompound(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @notice Toggles the activation of COMP rewards.
    function toggleCompRewardsActivation() external onlyOwner {
        bool newCompRewardsActive = !isCompRewardsActive;
        isCompRewardsActive = newCompRewardsActive;
        emit CompRewardsActive(newCompRewardsActive);
    }

    /// @notice Sets the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    function setPauseStatus(address _poolTokenAddress) external onlyOwner {
        bool newPauseStatus = !paused[_poolTokenAddress];
        paused[_poolTokenAddress] = newPauseStatus;
        emit PauseStatusSet(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Creates markets.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @return The results of entered.
    function createMarket(address _poolTokenAddress)
        external
        onlyMarketsManager
        returns (uint256[] memory)
    {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        return comptroller.enterMarkets(marketToEnter);
    }

    /// GETTERS ///

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolTokenAddress, PositionType _positionType)
        external
        view
        returns (address head)
    {
        if (_positionType == PositionType.SUPPLIERS_IN_P2P)
            head = suppliersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.SUPPLIERS_ON_POOL)
            head = suppliersOnPool[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.BORROWERS_IN_P2P)
            head = borrowersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.BORROWERS_ON_POOL)
            head = borrowersOnPool[_poolTokenAddress].getHead();
    }

    /// @notice Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolTokenAddress,
        PositionType _positionType,
        address _user
    ) external view returns (address next) {
        if (_positionType == PositionType.SUPPLIERS_IN_P2P)
            next = suppliersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.SUPPLIERS_ON_POOL)
            next = suppliersOnPool[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.BORROWERS_IN_P2P)
            next = borrowersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.BORROWERS_ON_POOL)
            next = borrowersOnPool[_poolTokenAddress].getNext(_user);
    }

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine liquidity for.
    /// @return collateralValue The collateral value of the user.
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum possible debt value of the user.
    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
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
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        LiquidityData memory data;
        AssetLiquidityData memory assetData;
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];

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
    ) public view returns (AssetLiquidityData memory assetData) {
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

    /// @dev Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum debt value possible of the user.
    function _getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (uint256 debtValue, uint256 maxDebtValue) {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];

            // Calling accrueInterest so that computation in getUserLiquidityDataForAsset() are the most accurate ones.
            ICToken(poolTokenEntered).accrueInterest();
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
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
    function _getUserSupplyBalanceInOf(address _poolTokenAddress, address _user)
        internal
        view
        returns (uint256)
    {
        (uint256 supplyP2PExchangeRate, ) = marketsManager.getUpdatedP2PExchangeRates(
            _poolTokenAddress
        );

        return
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P.mul(supplyP2PExchangeRate) +
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
        view
        returns (uint256)
    {
        (, uint256 borrowP2PExchangeRate) = marketsManager.getUpdatedP2PExchangeRates(
            _poolTokenAddress
        );

        return
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P.mul(borrowP2PExchangeRate) +
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
