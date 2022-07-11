// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IExitPositionsManager.sol";

import "./PositionsManagerUtils.sol";

/// @title ExitPositionsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Morpho's exit points: withdraw, repay and liquidate.
contract ExitPositionsManager is IExitPositionsManager, PositionsManagerUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;
    using Math for uint256;

    /// EVENTS ///

    /// @notice Emitted when a withdrawal happens.
    /// @param _supplier The address of the supplier whose supply is withdrawn.
    /// @param _receiver The address receiving the tokens.
    /// @param _poolTokenAddress The address of the market from where assets are withdrawn.
    /// @param _amount The amount of assets withdrawn (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Withdrawn(
        address indexed _supplier,
        address indexed _receiver,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a repayment happens.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _poolTokenAddress The address of the market where assets are repaid.
    /// @param _amount The amount of assets repaid (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event Repaid(
        address indexed _repayer,
        address indexed _onBehalf,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a liquidation happens.
    /// @param _liquidator The address of the liquidator.
    /// @param _liquidated The address of the liquidated.
    /// @param _poolTokenBorrowedAddress The address of the borrowed asset.
    /// @param _amountRepaid The amount of borrowed asset repaid (in underlying).
    /// @param _poolTokenCollateralAddress The address of the collateral asset seized.
    /// @param _amountSeized The amount of collateral asset seized (in underlying).
    event Liquidated(
        address _liquidator,
        address indexed _liquidated,
        address indexed _poolTokenBorrowedAddress,
        uint256 _amountRepaid,
        address indexed _poolTokenCollateralAddress,
        uint256 _amountSeized
    );

    /// ERRORS ///

    /// @notice Thrown when user is not a member of the market.
    error UserNotMemberOfMarket();

    /// @notice Thrown when the user does not have enough remaining collateral to withdraw.
    error UnauthorisedWithdraw();

    /// @notice Thrown when the positions of the user is not liquidatable.
    error UnauthorisedLiquidate();

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct WithdrawVars {
        uint256 remainingGasForMatching;
        uint256 remainingToWithdraw;
        uint256 poolSupplyIndex;
        uint256 p2pSupplyIndex;
        uint256 onPoolSupply;
        uint256 toWithdraw;
    }

    // Struct to avoid stack too deep.
    struct RepayVars {
        uint256 remainingGasForMatching;
        uint256 remainingToRepay;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 borrowedOnPool;
        uint256 feeToRepay;
        uint256 toRepay;
    }

    // Struct to avoid stack too deep.
    struct LiquidateVars {
        uint256 liquidationBonus; // The liquidation bonus on Aave.
        uint256 collateralReserveDecimals; // The number of decimals of the collateral asset in the reserve.
        uint256 collateralTokenUnit; // The collateral token unit considering its decimals.
        uint256 borrowedReserveDecimals; // The number of decimals of the borrowed asset in the reserve.
        uint256 borrowedTokenUnit; // The unit of borrowed token considering its decimals.
    }

    // Struct to avoid stack too deep.
    struct HealthFactorVars {
        uint256 i;
        bytes32 userMarkets;
        uint256 numberOfMarketsCreated;
    }

    /// LOGIC ///

    /// @dev Implements withdraw logic with security checks.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function withdrawLogic(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        if (_receiver == address(0)) revert AddressIsZero();

        _updateIndexes(_poolTokenAddress);
        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(_poolTokenAddress, _supplier),
            _amount
        );
        if (toWithdraw == 0) revert UserNotMemberOfMarket();

        if (!_withdrawAllowed(_supplier, _poolTokenAddress, toWithdraw))
            revert UnauthorisedWithdraw();

        _safeWithdrawLogic(_poolTokenAddress, toWithdraw, _supplier, _receiver, _maxGasForMatching);
    }

    /// @dev Implements repay logic with security checks.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function repayLogic(
        address _poolTokenAddress,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();

        _updateIndexes(_poolTokenAddress);
        uint256 toRepay = Math.min(
            _getUserBorrowBalanceInOf(_poolTokenAddress, _onBehalf),
            _amount
        );
        if (toRepay == 0) revert UserNotMemberOfMarket();

        _safeRepayLogic(_poolTokenAddress, _repayer, _onBehalf, toRepay, _maxGasForMatching);
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowedAddress The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateralAddress The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidateLogic(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external {
        bytes32 userMarkets = userMarkets[_borrower];
        if (
            !_isBorrowing(userMarkets, borrowMask[_poolTokenBorrowedAddress]) ||
            !_isSupplying(userMarkets, borrowMask[_poolTokenCollateralAddress])
        ) revert UserNotMemberOfMarket();

        _updateIndexes(_poolTokenBorrowedAddress);
        _updateIndexes(_poolTokenCollateralAddress);

        if (!_liquidationAllowed(_borrower)) revert UnauthorisedLiquidate();

        LiquidateVars memory vars;
        address tokenBorrowedAddress = IAToken(_poolTokenBorrowedAddress)
        .UNDERLYING_ASSET_ADDRESS();

        uint256 amountToLiquidate = Math.min(
            _amount,
            _getUserBorrowBalanceInOf(_poolTokenBorrowedAddress, _borrower).percentMul(
                DEFAULT_LIQUIDATION_CLOSE_FACTOR
            ) // Max liquidatable debt.
        );

        address tokenCollateralAddress = IAToken(_poolTokenCollateralAddress)
        .UNDERLYING_ASSET_ADDRESS();

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        (, , vars.liquidationBonus, vars.collateralReserveDecimals, ) = pool
        .getConfiguration(tokenCollateralAddress)
        .getParamsMemory();
        (, , , vars.borrowedReserveDecimals, ) = pool
        .getConfiguration(tokenBorrowedAddress)
        .getParamsMemory();

        unchecked {
            vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;
            vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;
        }

        uint256 borrowedTokenPrice = oracle.getAssetPrice(tokenBorrowedAddress);
        uint256 collateralPrice = oracle.getAssetPrice(tokenCollateralAddress);
        uint256 amountToSeize = ((amountToLiquidate *
            borrowedTokenPrice *
            vars.collateralTokenUnit) / (vars.borrowedTokenUnit * collateralPrice))
        .percentMul(vars.liquidationBonus);

        uint256 collateralBalance = _getUserSupplyBalanceInOf(
            _poolTokenCollateralAddress,
            _borrower
        );

        if (amountToSeize > collateralBalance) {
            amountToSeize = collateralBalance;
            amountToLiquidate = ((collateralBalance * collateralPrice * vars.borrowedTokenUnit) /
                (borrowedTokenPrice * vars.collateralTokenUnit))
            .percentDiv(vars.liquidationBonus);
        }

        _safeRepayLogic(_poolTokenBorrowedAddress, msg.sender, _borrower, amountToLiquidate, 0);
        _safeWithdrawLogic(_poolTokenCollateralAddress, amountToSeize, _borrower, msg.sender, 0);

        emit Liquidated(
            msg.sender,
            _borrower,
            _poolTokenBorrowedAddress,
            amountToLiquidate,
            _poolTokenCollateralAddress,
            amountToSeize
        );
    }

    /// INTERNAL ///

    /// @dev Implements withdraw logic without security checks.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function _safeWithdrawLogic(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) internal {
        ERC20 underlyingToken = ERC20(underlyingToken[_poolTokenAddress]);
        WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolSupplyIndex = poolIndexes[_poolTokenAddress].poolSupplyIndex;

        /// Soft withdraw ///

        vars.onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
        if (vars.onPoolSupply > 0) {
            vars.toWithdraw = Math.min(
                vars.onPoolSupply.rayMul(vars.poolSupplyIndex),
                vars.remainingToWithdraw
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                vars.onPoolSupply,
                vars.toWithdraw.rayDiv(vars.poolSupplyIndex)
            );

            if (vars.remainingToWithdraw == 0) {
                _updateSupplierInDS(_poolTokenAddress, _supplier);

                if (
                    supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P == 0 &&
                    supplyBalanceInOf[_poolTokenAddress][_supplier].onPool == 0
                ) _setSupplying(_supplier, borrowMask[_poolTokenAddress], false);

                _withdrawFromPool(underlyingToken, _poolTokenAddress, vars.toWithdraw); // Reverts on error.
                underlyingToken.safeTransfer(_receiver, _amount);

                emit Withdrawn(
                    _supplier,
                    _receiver,
                    _poolTokenAddress,
                    _amount,
                    supplyBalanceInOf[_poolTokenAddress][_supplier].onPool,
                    supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P
                );

                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];

        supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
            vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex)
        ); // In peer-to-peer supply unit.
        _updateSupplierInDS(_poolTokenAddress, _supplier);

        /// Transfer withdraw ///

        // Reduce peer-to-peer supply delta first if any.
        if (vars.remainingToWithdraw > 0 && delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.rayMul(vars.poolSupplyIndex),
                vars.remainingToWithdraw
            ); // In underlying.

            delta.p2pSupplyDelta = delta.p2pSupplyDelta.zeroFloorSub(
                vars.remainingToWithdraw.rayDiv(vars.poolSupplyIndex)
            );
            delta.p2pSupplyAmount -= matchedDelta.rayDiv(vars.p2pSupplyIndex);
            vars.toWithdraw += matchedDelta;
            vars.remainingToWithdraw -= matchedDelta;
            emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pSupplyDelta);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        // Match pool suppliers if any.
        if (
            vars.remainingToWithdraw > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            suppliersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            (uint256 matched, uint256 gasConsumedInMatching) = _matchSuppliers(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                vars.remainingGasForMatching
            );
            if (vars.remainingGasForMatching <= gasConsumedInMatching)
                vars.remainingGasForMatching = 0;
            else vars.remainingGasForMatching -= gasConsumedInMatching;

            if (matched > 0) {
                vars.remainingToWithdraw -= matched;
                vars.toWithdraw += matched;
            }
        }

        if (vars.toWithdraw > 0)
            _withdrawFromPool(underlyingToken, _poolTokenAddress, vars.toWithdraw); // Reverts on error.

        /// Hard withdraw ///

        // Unmatch peer-to-peer borrowers.
        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = _unmatchBorrowers(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                vars.remainingGasForMatching
            );

            // If unmatched does not cover remainingToWithdraw, the difference is added to the borrow peer-to-peer delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.p2pBorrowDelta += (vars.remainingToWithdraw - unmatched).rayDiv(
                    poolIndexes[_poolTokenAddress].poolBorrowIndex
                );
                emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
            }

            delta.p2pSupplyAmount -= Math.min(
                delta.p2pSupplyAmount,
                vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex)
            );
            delta.p2pBorrowAmount -= Math.min(
                delta.p2pBorrowAmount,
                unmatched.rayDiv(p2pBorrowIndex[_poolTokenAddress])
            );
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _borrowFromPool(underlyingToken, vars.remainingToWithdraw); // Reverts on error.
        }

        if (
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P == 0 &&
            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool == 0
        ) _setSupplying(_supplier, borrowMask[_poolTokenAddress], false);
        underlyingToken.safeTransfer(_receiver, _amount);

        emit Withdrawn(
            _supplier,
            _receiver,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool,
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P
        );
    }

    /// @dev Implements repay logic without security checks.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function _safeRepayLogic(
        address _poolTokenAddress,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        ERC20 underlyingToken = ERC20(underlyingToken[_poolTokenAddress]);
        underlyingToken.safeTransferFrom(_repayer, address(this), _amount);
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = poolIndexes[_poolTokenAddress].poolBorrowIndex;

        /// Soft repay ///

        vars.borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_onBehalf].onPool;
        if (vars.borrowedOnPool > 0) {
            vars.toRepay = Math.min(
                vars.borrowedOnPool.rayMul(vars.poolBorrowIndex),
                vars.remainingToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            borrowBalanceInOf[_poolTokenAddress][_onBehalf].onPool -= Math.min(
                vars.borrowedOnPool,
                vars.toRepay.rayDiv(vars.poolBorrowIndex)
            ); // In adUnit.

            if (vars.remainingToRepay == 0) {
                _updateBorrowerInDS(_poolTokenAddress, _onBehalf);
                _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

                if (
                    borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P == 0 &&
                    borrowBalanceInOf[_poolTokenAddress][_onBehalf].onPool == 0
                ) _setBorrowing(_onBehalf, borrowMask[_poolTokenAddress], false);

                emit Repaid(
                    _repayer,
                    _onBehalf,
                    _poolTokenAddress,
                    _amount,
                    borrowBalanceInOf[_poolTokenAddress][_onBehalf].onPool,
                    borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P
                );

                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolTokenAddress];
        vars.poolSupplyIndex = poolIndexes[_poolTokenAddress].poolSupplyIndex;
        borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P -= Math.min(
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P,
            vars.remainingToRepay.rayDiv(vars.p2pBorrowIndex)
        ); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(_poolTokenAddress, _onBehalf);

        // Reduce peer-to-peer borrow delta first if any.
        if (vars.remainingToRepay > 0 && delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex),
                vars.remainingToRepay
            ); // In underlying.

            delta.p2pBorrowDelta = delta.p2pBorrowDelta.zeroFloorSub(
                vars.remainingToRepay.rayDiv(vars.poolBorrowIndex)
            );
            delta.p2pBorrowAmount -= matchedDelta.rayDiv(vars.p2pBorrowIndex);
            vars.toRepay += matchedDelta;
            vars.remainingToRepay -= matchedDelta;
            emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        // Repay the fee.
        if (vars.remainingToRepay > 0) {
            // Fee = (p2pBorrowAmount - p2pBorrowDelta) - (p2pSupplyAmount - p2pSupplyDelta).
            // No need to subtract p2pBorrowDelta as it is zero.
            vars.feeToRepay = Math.zeroFloorSub(
                delta.p2pBorrowAmount.rayMul(vars.p2pBorrowIndex),
                (delta.p2pSupplyAmount.rayMul(vars.p2pSupplyIndex) -
                    delta.p2pSupplyDelta.rayMul(vars.poolSupplyIndex))
            );

            if (vars.feeToRepay > 0) {
                uint256 feeRepaid = Math.min(vars.feeToRepay, vars.remainingToRepay);
                vars.remainingToRepay -= feeRepaid;
                delta.p2pBorrowAmount -= feeRepaid.rayDiv(vars.p2pBorrowIndex);
                emit P2PAmountsUpdated(
                    _poolTokenAddress,
                    delta.p2pSupplyAmount,
                    delta.p2pBorrowAmount
                );
            }
        }

        /// Transfer repay ///

        // Match pool borrowers if any.
        if (
            vars.remainingToRepay > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            borrowersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            (uint256 matched, uint256 gasConsumedInMatching) = _matchBorrowers(
                _poolTokenAddress,
                vars.remainingToRepay,
                vars.remainingGasForMatching
            );
            if (vars.remainingGasForMatching <= gasConsumedInMatching)
                vars.remainingGasForMatching = 0;
            else vars.remainingGasForMatching -= gasConsumedInMatching;

            if (matched > 0) {
                vars.remainingToRepay -= matched;
                vars.toRepay += matched;
            }
        }

        _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

        /// Hard repay ///

        // Unmatch peer-to-peer suppliers.
        if (vars.remainingToRepay > 0) {
            uint256 unmatched = _unmatchSuppliers(
                _poolTokenAddress,
                vars.remainingToRepay,
                vars.remainingGasForMatching
            );

            // If unmatched does not cover remainingToRepay, the difference is added to the supply peer-to-peer delta.
            if (unmatched < vars.remainingToRepay) {
                delta.p2pSupplyDelta += (vars.remainingToRepay - unmatched).rayDiv(
                    vars.poolSupplyIndex
                );
                emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pSupplyDelta);
            }

            // Math.min as the last decimal might flip.
            delta.p2pSupplyAmount -= Math.min(
                unmatched.rayDiv(vars.p2pSupplyIndex),
                delta.p2pSupplyAmount
            );
            delta.p2pBorrowAmount -= Math.min(
                vars.remainingToRepay.rayDiv(vars.p2pBorrowIndex),
                delta.p2pBorrowAmount
            );
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _supplyToPool(underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        if (
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P == 0 &&
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].onPool == 0
        ) _setBorrowing(_onBehalf, borrowMask[_poolTokenAddress], false);

        emit Repaid(
            _repayer,
            _onBehalf,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].onPool,
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P
        );
    }

    /// @dev Returns the health factor of the user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw from.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @return The health factor of the user.
    function _getUserHealthFactor(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount
    ) internal returns (uint256) {
        HealthFactorVars memory vars;
        vars.userMarkets = userMarkets[_user];

        // If the user is not borrowing any asset, return an infinite health factor.
        if (!_isBorrowingAny(vars.userMarkets)) return type(uint256).max;

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        Types.AssetLiquidityData memory assetData;
        Types.LiquidityData memory liquidityData;
        vars.numberOfMarketsCreated = marketsCreated.length;

        for (; vars.i < vars.numberOfMarketsCreated; ) {
            address poolToken = marketsCreated[vars.i];
            bytes32 borrowMask = borrowMask[poolToken];

            if (_isSupplyingOrBorrowing(vars.userMarkets, borrowMask)) {
                if (poolToken != _poolTokenAddress) _updateIndexes(poolToken);

                address underlyingToken = underlyingToken[poolToken];
                assetData.underlyingPrice = oracle.getAssetPrice(underlyingToken); // In ETH.
                (
                    assetData.ltv,
                    assetData.liquidationThreshold,
                    ,
                    assetData.reserveDecimals,

                ) = pool.getConfiguration(underlyingToken).getParamsMemory();
                assetData.tokenUnit = 10**assetData.reserveDecimals;

                if (_isBorrowing(vars.userMarkets, borrowMask))
                    liquidityData.debtValue += (_getUserBorrowBalanceInOf(poolToken, _user) *
                        assetData.underlyingPrice)
                    .divUp(assetData.tokenUnit);

                if (_isSupplying(vars.userMarkets, borrowMask)) {
                    assetData.collateralValue =
                        (_getUserSupplyBalanceInOf(poolToken, _user) * assetData.underlyingPrice) /
                        assetData.tokenUnit;
                    liquidityData.liquidationThresholdValue += assetData.collateralValue.percentMul(
                        assetData.liquidationThreshold
                    );
                }

                if (_poolTokenAddress == poolToken && _withdrawnAmount > 0)
                    liquidityData.liquidationThresholdValue -= (_withdrawnAmount *
                        assetData.underlyingPrice)
                    .divUp(assetData.tokenUnit)
                    .percentMul(assetData.liquidationThreshold);
            }

            unchecked {
                ++vars.i;
            }
        }

        return liquidityData.liquidationThresholdValue.wadDiv(liquidityData.debtValue);
    }

    /// @dev Checks whether the user can withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @return Whether the withdraw is allowed or not.
    function _withdrawAllowed(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount
    ) internal returns (bool) {
        return
            _getUserHealthFactor(_user, _poolTokenAddress, _withdrawnAmount) >=
            HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /// @dev Checks if the user is liquidatable.
    /// @param _user The user to check.
    /// @return Whether the user is liquidatable or not.
    function _liquidationAllowed(address _user) internal returns (bool) {
        return _getUserHealthFactor(_user, address(0), 0) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }
}
