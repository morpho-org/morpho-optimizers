// SPDX-License-Identifier: AGPL-3.0-only
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
    /// @param _poolToken The address of the market from where assets are withdrawn.
    /// @param _amount The amount of assets withdrawn (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Withdrawn(
        address indexed _supplier,
        address indexed _receiver,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a repayment happens.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _poolToken The address of the market where assets are repaid.
    /// @param _amount The amount of assets repaid (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event Repaid(
        address indexed _repayer,
        address indexed _onBehalf,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a liquidation happens.
    /// @param _liquidator The address of the liquidator.
    /// @param _liquidated The address of the liquidated.
    /// @param _poolTokenBorrowed The address of the borrowed asset.
    /// @param _amountRepaid The amount of borrowed asset repaid (in underlying).
    /// @param _poolTokenCollateral The address of the collateral asset seized.
    /// @param _amountSeized The amount of collateral asset seized (in underlying).
    event Liquidated(
        address _liquidator,
        address indexed _liquidated,
        address indexed _poolTokenBorrowed,
        uint256 _amountRepaid,
        address indexed _poolTokenCollateral,
        uint256 _amountSeized
    );

    /// @notice Emitted when the peer-to-peer deltas are increased by the governance.
    /// @param _poolToken The address of the market on which the deltas were increased.
    /// @param _amount The amount that has been added to the deltas (in underlying).
    event P2PDeltasIncreased(address indexed _poolToken, uint256 _amount);

    /// ERRORS ///

    /// @notice Thrown when user is not a member of the market.
    error UserNotMemberOfMarket();

    /// @notice Thrown when the user does not have enough remaining collateral to withdraw.
    error UnauthorisedWithdraw();

    /// @notice Thrown when the positions of the user is not liquidatable.
    error UnauthorisedLiquidate();

    /// @notice Thrown when someone tries to withdraw but the withdraw is paused.
    error WithdrawIsPaused();

    /// @notice Thrown when someone tries to repay but the repay is paused.
    error RepayIsPaused();

    /// @notice Thrown when someone tries to liquidate but the liquidation with this asset as collateral is paused.
    error LiquidateCollateralIsPaused();

    /// @notice Thrown when someone tries to liquidate but the liquidation with this asset as debt is paused.
    error LiquidateBorrowIsPaused();

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
        uint256 collateralBalance; // The collateral balance of the borrower.
        uint256 collateralPrice; // The price of the collateral token.
        uint256 amountToSeize; // The amount of collateral token to seize.
        uint256 borrowedReserveDecimals; // The number of decimals of the borrowed asset in the reserve.
        uint256 borrowedTokenUnit; // The unit of borrowed token considering its decimals.
        uint256 borrowedTokenPrice; // The price of the borrowed token.
        uint256 amountToLiquidate; // The amount of debt token to repay.
        uint256 closeFactor; // The close factor used during the liquidation.
        bool liquidationAllowed; // Whether the liquidation is allowed or not.
    }

    /// LOGIC ///

    /// @dev Implements withdraw logic with security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function withdrawLogic(
        address _poolToken,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        if (_receiver == address(0)) revert AddressIsZero();
        if (!market[_poolToken].isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isWithdrawPaused) revert WithdrawIsPaused();

        _updateIndexes(_poolToken);
        uint256 toWithdraw = Math.min(_getUserSupplyBalanceInOf(_poolToken, _supplier), _amount);
        if (toWithdraw == 0) revert UserNotMemberOfMarket();

        if (!_withdrawAllowed(_supplier, _poolToken, toWithdraw)) revert UnauthorisedWithdraw();

        _unsafeWithdrawLogic(_poolToken, toWithdraw, _supplier, _receiver, _maxGasForMatching);
    }

    /// @dev Implements repay logic with security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function repayLogic(
        address _poolToken,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        if (!market[_poolToken].isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isRepayPaused) revert RepayIsPaused();

        _updateIndexes(_poolToken);
        uint256 toRepay = Math.min(_getUserBorrowBalanceInOf(_poolToken, _onBehalf), _amount);
        if (toRepay == 0) revert UserNotMemberOfMarket();

        _unsafeRepayLogic(_poolToken, _repayer, _onBehalf, toRepay, _maxGasForMatching);
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowed The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateral The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidateLogic(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external {
        if (_amount == 0) revert AmountIsZero();
        Types.Market memory collateralMarket = market[_poolTokenCollateral];
        if (!collateralMarket.isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolTokenCollateral].isLiquidateCollateralPaused)
            revert LiquidateCollateralIsPaused();
        Types.Market memory borrowMarket = market[_poolTokenBorrowed];
        Types.MarketPauseStatus memory borrowPauseStatus = marketPauseStatus[_poolTokenBorrowed];
        if (!borrowMarket.isCreated) revert MarketNotCreated();
        if (borrowPauseStatus.isLiquidateBorrowPaused) revert LiquidateBorrowIsPaused();

        if (
            !_isBorrowingAndSupplying(
                userMarkets[_borrower],
                borrowMask[_poolTokenBorrowed],
                borrowMask[_poolTokenCollateral]
            )
        ) revert UserNotMemberOfMarket();

        _updateIndexes(_poolTokenBorrowed);
        _updateIndexes(_poolTokenCollateral);

        LiquidateVars memory vars;
        (vars.liquidationAllowed, vars.closeFactor) = _liquidationAllowed(
            _borrower,
            borrowPauseStatus.isDeprecated
        );
        if (!vars.liquidationAllowed) revert UnauthorisedLiquidate();

        vars.amountToLiquidate = Math.min(
            _amount,
            _getUserBorrowBalanceInOf(_poolTokenBorrowed, _borrower).percentMul(vars.closeFactor) // Max liquidatable debt.
        );

        address tokenBorrowed = borrowMarket.underlyingToken;
        address tokenCollateral = market[_poolTokenCollateral].underlyingToken;

        ILendingPool poolMem = pool;
        (, , vars.liquidationBonus, vars.collateralReserveDecimals, ) = poolMem
        .getConfiguration(tokenCollateral)
        .getParamsMemory();
        (, , , vars.borrowedReserveDecimals, ) = poolMem
        .getConfiguration(tokenBorrowed)
        .getParamsMemory();

        unchecked {
            vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;
            vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;
        }

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        vars.borrowedTokenPrice = oracle.getAssetPrice(tokenBorrowed);
        vars.collateralPrice = oracle.getAssetPrice(tokenCollateral);
        vars.amountToSeize = ((vars.amountToLiquidate *
            vars.borrowedTokenPrice *
            vars.collateralTokenUnit) / (vars.borrowedTokenUnit * vars.collateralPrice))
        .percentMul(vars.liquidationBonus);

        vars.collateralBalance = _getUserSupplyBalanceInOf(_poolTokenCollateral, _borrower);

        if (vars.amountToSeize > vars.collateralBalance) {
            vars.amountToSeize = vars.collateralBalance;
            vars.amountToLiquidate = ((vars.collateralBalance *
                vars.collateralPrice *
                vars.borrowedTokenUnit) / (vars.borrowedTokenPrice * vars.collateralTokenUnit))
            .percentDiv(vars.liquidationBonus);
        }

        _unsafeRepayLogic(_poolTokenBorrowed, msg.sender, _borrower, vars.amountToLiquidate, 0);
        _unsafeWithdrawLogic(_poolTokenCollateral, vars.amountToSeize, _borrower, msg.sender, 0);

        emit Liquidated(
            msg.sender,
            _borrower,
            _poolTokenBorrowed,
            vars.amountToLiquidate,
            _poolTokenCollateral,
            vars.amountToSeize
        );
    }

    /// @notice Implements increaseP2PDeltas logic.
    /// @dev The current Morpho supply on the pool might not be enough to borrow `_amount` before resupplying it.
    /// In this case, consider calling this function multiple times.
    /// @param _poolToken The address of the market on which to increase deltas.
    /// @param _amount The maximum amount to add to the deltas (in underlying).
    function increaseP2PDeltasLogic(address _poolToken, uint256 _amount)
        external
        isMarketCreated(_poolToken)
    {
        _updateIndexes(_poolToken);

        Types.Delta storage deltas = deltas[_poolToken];
        Types.PoolIndexes memory poolIndexes = poolIndexes[_poolToken];

        _amount = Math.min(
            _amount,
            Math.min(
                deltas.p2pSupplyAmount.rayMul(p2pSupplyIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pSupplyDelta.rayMul(poolIndexes.poolSupplyIndex)
                ),
                deltas.p2pBorrowAmount.rayMul(p2pBorrowIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pBorrowDelta.rayMul(poolIndexes.poolBorrowIndex)
                )
            )
        );
        if (_amount == 0) revert AmountIsZero();

        deltas.p2pSupplyDelta += _amount.rayDiv(poolIndexes.poolSupplyIndex);
        deltas.p2pBorrowDelta += _amount.rayDiv(poolIndexes.poolBorrowIndex);
        emit P2PSupplyDeltaUpdated(_poolToken, deltas.p2pSupplyDelta);
        emit P2PBorrowDeltaUpdated(_poolToken, deltas.p2pBorrowDelta);

        ERC20 underlyingToken = ERC20(market[_poolToken].underlyingToken);
        _borrowFromPool(underlyingToken, _amount);
        _supplyToPool(underlyingToken, _amount);

        emit P2PDeltasIncreased(_poolToken, _amount);
    }

    /// INTERNAL ///

    /// @dev Implements withdraw logic without security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function _unsafeWithdrawLogic(
        address _poolToken,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) internal {
        ERC20 underlyingToken = ERC20(market[_poolToken].underlyingToken);
        WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolSupplyIndex = poolIndexes[_poolToken].poolSupplyIndex;

        Types.SupplyBalance storage supplierSupplyBalance = supplyBalanceInOf[_poolToken][
            _supplier
        ];

        /// Pool withdraw ///

        // Withdraw supply on pool.
        vars.onPoolSupply = supplierSupplyBalance.onPool;
        if (vars.onPoolSupply > 0) {
            vars.toWithdraw = Math.min(
                vars.onPoolSupply.rayMul(vars.poolSupplyIndex),
                vars.remainingToWithdraw
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            supplierSupplyBalance.onPool -= Math.min(
                vars.onPoolSupply,
                vars.toWithdraw.rayDiv(vars.poolSupplyIndex)
            );

            if (vars.remainingToWithdraw == 0) {
                _updateSupplierInDS(_poolToken, _supplier);

                if (supplierSupplyBalance.inP2P == 0 && supplierSupplyBalance.onPool == 0)
                    _setSupplying(_supplier, borrowMask[_poolToken], false);

                _withdrawFromPool(underlyingToken, _poolToken, vars.toWithdraw); // Reverts on error.
                underlyingToken.safeTransfer(_receiver, _amount);

                emit Withdrawn(
                    _supplier,
                    _receiver,
                    _poolToken,
                    _amount,
                    supplierSupplyBalance.onPool,
                    supplierSupplyBalance.inP2P
                );

                return;
            }
        }

        Types.Delta storage delta = deltas[_poolToken];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolToken];

        supplierSupplyBalance.inP2P -= Math.min(
            supplierSupplyBalance.inP2P,
            vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex)
        ); // In peer-to-peer supply unit.
        _updateSupplierInDS(_poolToken, _supplier);

        // Reduce the peer-to-peer supply delta.
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
            emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Transfer withdraw ///

        // Promote pool suppliers.
        if (
            vars.remainingToWithdraw > 0 &&
            !market[_poolToken].isP2PDisabled &&
            suppliersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, uint256 gasConsumedInMatching) = _matchSuppliers(
                _poolToken,
                vars.remainingToWithdraw,
                vars.remainingGasForMatching
            );
            if (vars.remainingGasForMatching <= gasConsumedInMatching)
                vars.remainingGasForMatching = 0;
            else vars.remainingGasForMatching -= gasConsumedInMatching;

            vars.remainingToWithdraw -= matched;
            vars.toWithdraw += matched;
        }

        if (vars.toWithdraw > 0) _withdrawFromPool(underlyingToken, _poolToken, vars.toWithdraw); // Reverts on error.

        /// Breaking withdraw ///

        // Demote peer-to-peer borrowers.
        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = _unmatchBorrowers(
                _poolToken,
                vars.remainingToWithdraw,
                vars.remainingGasForMatching
            );

            // Increase the peer-to-peer borrow delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.p2pBorrowDelta += (vars.remainingToWithdraw - unmatched).rayDiv(
                    poolIndexes[_poolToken].poolBorrowIndex
                );
                emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
            }

            delta.p2pSupplyAmount -= Math.min(
                delta.p2pSupplyAmount,
                vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex)
            );
            delta.p2pBorrowAmount -= Math.min(
                delta.p2pBorrowAmount,
                unmatched.rayDiv(p2pBorrowIndex[_poolToken])
            );
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _borrowFromPool(underlyingToken, vars.remainingToWithdraw); // Reverts on error.
        }

        if (supplierSupplyBalance.inP2P == 0 && supplierSupplyBalance.onPool == 0)
            _setSupplying(_supplier, borrowMask[_poolToken], false);
        underlyingToken.safeTransfer(_receiver, _amount);

        emit Withdrawn(
            _supplier,
            _receiver,
            _poolToken,
            _amount,
            supplierSupplyBalance.onPool,
            supplierSupplyBalance.inP2P
        );
    }

    /// @dev Implements repay logic without security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function _unsafeRepayLogic(
        address _poolToken,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        ERC20 underlyingToken = ERC20(market[_poolToken].underlyingToken);
        underlyingToken.safeTransferFrom(_repayer, address(this), _amount);
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = poolIndexes[_poolToken].poolBorrowIndex;

        Types.BorrowBalance storage borrowerBorrowBalance = borrowBalanceInOf[_poolToken][
            _onBehalf
        ];

        /// Pool repay ///

        // Repay borrow on pool.
        vars.borrowedOnPool = borrowerBorrowBalance.onPool;
        if (vars.borrowedOnPool > 0) {
            vars.toRepay = Math.min(
                vars.borrowedOnPool.rayMul(vars.poolBorrowIndex),
                vars.remainingToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            borrowerBorrowBalance.onPool -= Math.min(
                vars.borrowedOnPool,
                vars.toRepay.rayDiv(vars.poolBorrowIndex)
            ); // In adUnit.

            if (vars.remainingToRepay == 0) {
                _updateBorrowerInDS(_poolToken, _onBehalf);
                _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

                if (borrowerBorrowBalance.inP2P == 0 && borrowerBorrowBalance.onPool == 0)
                    _setBorrowing(_onBehalf, borrowMask[_poolToken], false);

                emit Repaid(
                    _repayer,
                    _onBehalf,
                    _poolToken,
                    _amount,
                    borrowerBorrowBalance.onPool,
                    borrowerBorrowBalance.inP2P
                );

                return;
            }
        }

        Types.Delta storage delta = deltas[_poolToken];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolToken];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolToken];
        vars.poolSupplyIndex = poolIndexes[_poolToken].poolSupplyIndex;
        borrowerBorrowBalance.inP2P -= Math.min(
            borrowerBorrowBalance.inP2P,
            vars.remainingToRepay.rayDiv(vars.p2pBorrowIndex)
        ); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(_poolToken, _onBehalf);

        // Reduce the peer-to-peer borrow delta.
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
            emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        // Repay the fee.
        if (vars.remainingToRepay > 0) {
            // Fee = (p2pBorrowAmount - p2pBorrowDelta) - (p2pSupplyAmount - p2pSupplyDelta).
            // No need to subtract p2pBorrowDelta as it is zero.
            vars.feeToRepay = Math.zeroFloorSub(
                delta.p2pBorrowAmount.rayMul(vars.p2pBorrowIndex),
                delta.p2pSupplyAmount.rayMul(vars.p2pSupplyIndex).zeroFloorSub(
                    delta.p2pSupplyDelta.rayMul(vars.poolSupplyIndex)
                )
            );

            if (vars.feeToRepay > 0) {
                uint256 feeRepaid = Math.min(vars.feeToRepay, vars.remainingToRepay);
                vars.remainingToRepay -= feeRepaid;
                delta.p2pBorrowAmount -= feeRepaid.rayDiv(vars.p2pBorrowIndex);
                emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
            }
        }

        /// Transfer repay ///

        // Promote pool borrowers.
        if (
            vars.remainingToRepay > 0 &&
            !market[_poolToken].isP2PDisabled &&
            borrowersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, uint256 gasConsumedInMatching) = _matchBorrowers(
                _poolToken,
                vars.remainingToRepay,
                vars.remainingGasForMatching
            );
            if (vars.remainingGasForMatching <= gasConsumedInMatching)
                vars.remainingGasForMatching = 0;
            else vars.remainingGasForMatching -= gasConsumedInMatching;

            vars.remainingToRepay -= matched;
            vars.toRepay += matched;
        }

        _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

        /// Breaking repay ///

        // Demote peer-to-peer suppliers.
        if (vars.remainingToRepay > 0) {
            uint256 unmatched = _unmatchSuppliers(
                _poolToken,
                vars.remainingToRepay,
                vars.remainingGasForMatching
            );

            // Increase the peer-to-peer supply delta.
            if (unmatched < vars.remainingToRepay) {
                delta.p2pSupplyDelta += (vars.remainingToRepay - unmatched).rayDiv(
                    vars.poolSupplyIndex
                );
                emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
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
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _supplyToPool(underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        if (borrowerBorrowBalance.inP2P == 0 && borrowerBorrowBalance.onPool == 0)
            _setBorrowing(_onBehalf, borrowMask[_poolToken], false);

        emit Repaid(
            _repayer,
            _onBehalf,
            _poolToken,
            _amount,
            borrowerBorrowBalance.onPool,
            borrowerBorrowBalance.inP2P
        );
    }

    /// @dev Returns the health factor of the user.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw from.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @return The health factor of the user.
    function _getUserHealthFactor(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount
    ) internal returns (uint256) {
        // If the user is not borrowing any asset, return an infinite health factor.
        if (!_isBorrowingAny(userMarkets[_user])) return type(uint256).max;

        Types.LiquidityData memory values = _liquidityData(_user, _poolToken, _withdrawnAmount, 0);

        return values.debtEth > 0 ? values.maxDebtEth.wadDiv(values.debtEth) : type(uint256).max;
    }

    /// @dev Checks whether the user can withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @return Whether the withdraw is allowed or not.
    function _withdrawAllowed(
        address _user,
        address _poolToken,
        uint256 _withdrawnAmount
    ) internal returns (bool) {
        return
            _getUserHealthFactor(_user, _poolToken, _withdrawnAmount) >=
            HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /// @dev Returns whether a given user is liquidatable and the applicable close factor, given the deprecated status of the borrowed market.
    /// @param _user The user to check.
    /// @param _isDeprecated Whether the borrowed market is deprecated or not.
    /// @return liquidationAllowed Whether the liquidation is allowed or not.
    /// @return closeFactor The close factor to apply.
    function _liquidationAllowed(address _user, bool _isDeprecated)
        internal
        returns (bool liquidationAllowed, uint256 closeFactor)
    {
        if (_isDeprecated) {
            liquidationAllowed = true;
            closeFactor = MAX_BASIS_POINTS; // Allow liquidation of the whole debt.
        } else {
            liquidationAllowed = (_getUserHealthFactor(_user, address(0), 0) <
                HEALTH_FACTOR_LIQUIDATION_THRESHOLD);
            if (liquidationAllowed) closeFactor = DEFAULT_LIQUIDATION_CLOSE_FACTOR;
        }
    }
}
