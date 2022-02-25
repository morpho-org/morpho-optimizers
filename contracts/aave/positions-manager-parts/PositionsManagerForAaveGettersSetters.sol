// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "../interfaces/aave/IPriceOracleGetter.sol";

import "./PositionsManagerForAaveStorage.sol";

/// @title PositionsManagerForAaveGettersSetters.
/// @notice Getters and setters for PositionsManagerForAave, including externals, inernals, user-accessible and admin-only functions.
contract PositionsManagerForAaveGettersSetters is PositionsManagerForAaveStorage {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;

    /// External ///

    /// @notice Updates the `lendingPool` and the `dataProvider`.
    function updateAaveContracts() external {
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit AaveContractsUpdated(address(lendingPool), address(dataProvider));
    }

    /// @notice Sets the `aaveIncentivesController`.
    /// @param _aaveIncentivesController The address of the `aaveIncentivesController`.
    function setAaveIncentivesController(address _aaveIncentivesController)
        external
        onlyMarketsManagerOwner
    {
        aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
        emit AaveIncentivesControllerSet(_aaveIncentivesController);
    }

    /// @dev Sets `NDS`.
    /// @param _newNDS The new `NDS` value.
    function setNDS(uint8 _newNDS) external onlyMarketsManagerOwner {
        NDS = _newNDS;
        emit NDSSet(_newNDS);
    }

    /// @dev Sets `maxGas`.
    /// @param _maxGas The new `maxGas`.
    function setMaxGas(MaxGas memory _maxGas) external onlyMarketsManagerOwner {
        maxGas = _maxGas;
        emit MaxGasSet(_maxGas);
    }

    /// @dev Sets the threshold of a market.
    /// @param _poolTokenAddress The address of the market to set the threshold.
    /// @param _newThreshold The new threshold.
    function setThreshold(address _poolTokenAddress, uint256 _newThreshold)
        external
        onlyMarketsManager
    {
        threshold[_poolTokenAddress] = _newThreshold;
        emit ThresholdSet(_poolTokenAddress, _newThreshold);
    }

    /// @notice Sets the `_newTreasuryVaultAddress`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyMarketsManagerOwner {
        treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyMarketsManagerOwner {
        rewardsManager = IRewardsManager(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @notice Sets the pause status in case of emergency.
    /// @dev Note: the events are emitted through the Pausable contract.
    function setPauseStatus() external onlyMarketsManagerOwner {
        if (paused()) _unpause();
        else _pause();
    }

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

    /// @notice Returns the collateral value, debt value and max debt value of a given user (in ETH).
    /// @param _user The user to determine liquidity for.
    /// @return collateralValue The collateral value of the user (in ETH).
    /// @return debtValue The current debt value of the user (in ETH).
    /// @return maxDebtValue The maximum possible debt value of the user (in ETH).
    /// @return liquidationValue The value which made liquidation possible (in ETH).
    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue,
            uint256 liquidationValue
        )
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            collateralValue += assetData.collateralValue;
            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;
            liquidationValue += assetData.liquidationValue;
        }
    }

    /// @notice Returns the maximum amount available for withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
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
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = getUserLiquidityDataForAsset(_user, poolTokenEntered, oracle);

                data.maxDebtValue += assetData.maxDebtValue;
                data.debtValue += assetData.debtValue;
            }
        }

        assetData = getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        data.maxDebtValue += assetData.maxDebtValue;
        data.debtValue += assetData.debtValue;

        // Not possible to withdraw nor borrow
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        uint256 differenceInUnderlying = ((data.maxDebtValue - data.debtValue) *
            assetData.tokenUnit) / assetData.underlyingPrice;

        withdrawable =
            (assetData.collateralValue * assetData.tokenUnit) /
            assetData.underlyingPrice;
        if (assetData.ltv != 0) {
            withdrawable = Math.min(
                withdrawable,
                (differenceInUnderlying * MAX_BASIS_POINTS) / assetData.ltv
            );
        }

        borrowable = differenceInUnderlying;
    }

    /// Public ///

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        IPriceOracleGetter oracle
    ) public view returns (AssetLiquidityData memory assetData) {
        // Compute the current debt amount (in underlying)
        address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
        assetData.debtValue = _getUserBorrowBalanceInOf(
            _poolTokenAddress,
            _user,
            underlyingAddress
        );

        // Compute the current collateral amount (in underlying)
        assetData.collateralValue = _getUserSupplyBalanceInOf(
            _poolTokenAddress,
            _user,
            underlyingAddress
        );

        assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH
        (
            uint256 reserveDecimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = dataProvider.getReserveConfigurationData(underlyingAddress);
        assetData.ltv = ltv;
        assetData.liquidationThreshold = liquidationThreshold;
        assetData.tokenUnit = 10**reserveDecimals;

        // Then, convert values to ETH
        assetData.collateralValue =
            (assetData.collateralValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
        assetData.maxDebtValue = (assetData.collateralValue * ltv) / MAX_BASIS_POINTS;
        assetData.liquidationValue =
            (assetData.collateralValue * liquidationThreshold) /
            MAX_BASIS_POINTS;
        assetData.debtValue =
            (assetData.debtValue * assetData.underlyingPrice) /
            assetData.tokenUnit;
    }

    /// Internal ///

    /// @notice Checks whether the user can borrow/withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    function _checkUserLiquidity(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (debtValue > maxDebtValue) revert DebtValueAboveMax();
    }

    /// @notice Returns the debt value, max debt value of a given user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return debtValue The current debt value of the user (in ETH).
    /// @return maxDebtValue The maximum debt value possible of the user (in ETH).
    /// @return liquidationValue The value when liquidation is possible (in ETH).
    function _getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    )
        internal
        returns (
            uint256 debtValue,
            uint256 maxDebtValue,
            uint256 liquidationValue
        )
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        for (uint256 i; i < enteredMarkets[_user].length; i++) {
            address poolTokenEntered = enteredMarkets[_user][i];
            marketsManager.updateP2PExchangeRates(poolTokenEntered);
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            liquidationValue += assetData.liquidationValue;
            maxDebtValue += assetData.maxDebtValue;
            debtValue += assetData.debtValue;

            if (_poolTokenAddress == poolTokenEntered) {
                debtValue += (_borrowedAmount * assetData.underlyingPrice) / assetData.tokenUnit;
                maxDebtValue -= Math.min(
                    maxDebtValue,
                    (_withdrawnAmount * assetData.underlyingPrice * assetData.ltv) /
                        (assetData.tokenUnit * MAX_BASIS_POINTS)
                );
                liquidationValue -= Math.min(
                    liquidationValue,
                    (_withdrawnAmount * assetData.underlyingPrice * assetData.liquidationValue) /
                        (assetData.tokenUnit * MAX_BASIS_POINTS)
                );
            }
        }
    }

    /// @notice Returns the supply balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the supply amount.
    /// @param _underlyingTokenAddress The underlying token address related to this market.
    /// @return The supply balance of the user (in underlying).
    function _getUserSupplyBalanceInOf(
        address _poolTokenAddress,
        address _user,
        address _underlyingTokenAddress
    ) internal view returns (uint256) {
        return
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(
                marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
            ) +
            supplyBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedIncome(_underlyingTokenAddress)
            );
    }

    /// @notice Returns the borrow balance of `_user` in the `_poolTokenAddress` market.
    /// @param _user The address of the user.
    /// @param _poolTokenAddress The market where to get the borrow amount.
    /// @param _underlyingTokenAddress The underlying token address related to this market.
    /// @return The borrow balance of the user (in underlying).
    function _getUserBorrowBalanceInOf(
        address _poolTokenAddress,
        address _user,
        address _underlyingTokenAddress
    ) internal view returns (uint256) {
        return
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P.mulWadByRay(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            ) +
            borrowBalanceInOf[_poolTokenAddress][_user].onPool.mulWadByRay(
                lendingPool.getReserveNormalizedVariableDebt(_underlyingTokenAddress)
            );
    }

    ///@notice Enters the user into the market if not already there.
    ///@param _user The address of the user to update.
    ///@param _poolTokenAddress The address of the market to check.
    function _handleMembership(address _poolTokenAddress, address _user) internal {
        if (!userMembership[_poolTokenAddress][_user]) {
            userMembership[_poolTokenAddress][_user] = true;
            enteredMarkets[_user].push(_poolTokenAddress);
        }
    }
}
