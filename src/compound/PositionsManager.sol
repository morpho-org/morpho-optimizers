// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./interfaces/IPositionsManager.sol";
import "./interfaces/IWETH.sol";

import "./MatchingEngine.sol";

/// @title PositionsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Main Logic of Morpho Protocol, implementation of the 5 main functionalities: supply, borrow, withdraw, repay and liquidate.
contract PositionsManager is IPositionsManager, MatchingEngine {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;
    using Math for uint256;

    /// EVENTS ///

    /// @notice Emitted when a supply happens.
    /// @param _supplier The address of the account sending funds.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _poolToken The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Supplied(
        address indexed _supplier,
        address indexed _onBehalf,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a borrow happens.
    /// @param _borrower The address of the borrower.
    /// @param _poolToken The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update
    event Borrowed(
        address indexed _borrower,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

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

    /// @notice Emitted when the borrow peer-to-peer delta is updated.
    /// @param _poolToken The address of the market.
    /// @param _p2pBorrowDelta The borrow peer-to-peer delta after update.
    event P2PBorrowDeltaUpdated(address indexed _poolToken, uint256 _p2pBorrowDelta);

    /// @notice Emitted when the supply peer-to-peer delta is updated.
    /// @param _poolToken The address of the market.
    /// @param _p2pSupplyDelta The supply peer-to-peer delta after update.
    event P2PSupplyDeltaUpdated(address indexed _poolToken, uint256 _p2pSupplyDelta);

    /// @notice Emitted when the supply and borrow peer-to-peer amounts are updated.
    /// @param _poolToken The address of the market.
    /// @param _p2pSupplyAmount The supply peer-to-peer amount after update.
    /// @param _p2pBorrowAmount The borrow peer-to-peer amount after update.
    event P2PAmountsUpdated(
        address indexed _poolToken,
        uint256 _p2pSupplyAmount,
        uint256 _p2pBorrowAmount
    );

    /// ERRORS ///

    /// @notice Thrown when the amount repaid during the liquidation is above what is allowed to be repaid.
    error AmountAboveWhatAllowedToRepay();

    /// @notice Thrown when the borrow on Compound failed and throws back the Compound error code.
    error BorrowOnCompoundFailed(uint256 errorCode);

    /// @notice Thrown when the redeem on Compound failed and throws back the Compound error code.
    error RedeemOnCompoundFailed(uint256 errorCode);

    /// @notice Thrown when the repay on Compound failed and throws back the Compound error code.
    error RepayOnCompoundFailed(uint256 errorCode);

    /// @notice Thrown when the mint on Compound failed and throws back the Compound error code.
    error MintOnCompoundFailed(uint256 errorCode);

    /// @notice Thrown when user is not a member of the market.
    error UserNotMemberOfMarket();

    /// @notice Thrown when the user does not have enough remaining collateral to withdraw.
    error UnauthorisedWithdraw();

    /// @notice Thrown when the positions of the user is not liquidatable.
    error UnauthorisedLiquidate();

    /// @notice Thrown when the user does not have enough collateral for the borrow.
    error UnauthorisedBorrow();

    /// @notice Thrown when the amount desired for a withdrawal is too small.
    error WithdrawTooSmall();

    /// @notice Thrown when the address is zero.
    error AddressIsZero();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// @notice Thrown when a user tries to repay its debt after borrowing in the same block.
    error SameBlockBorrowRepay();

    /// @notice Thrown when someone tries to supply but the supply is paused.
    error SupplyIsPaused();

    /// @notice Thrown when someone tries to borrow but the borrow is paused.
    error BorrowIsPaused();

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
    struct SupplyVars {
        uint256 remainingToSupply;
        uint256 poolBorrowIndex;
        uint256 toRepay;
    }

    // Struct to avoid stack too deep.
    struct WithdrawVars {
        uint256 remainingGasForMatching;
        uint256 remainingToWithdraw;
        uint256 poolSupplyIndex;
        uint256 p2pSupplyIndex;
        uint256 toWithdraw;
        ERC20 underlyingToken;
    }

    // Struct to avoid stack too deep.
    struct RepayVars {
        uint256 remainingGasForMatching;
        uint256 remainingToRepay;
        uint256 maxToRepayOnPool;
        uint256 poolBorrowIndex;
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 borrowedOnPool;
        uint256 feeToRepay;
        uint256 toRepay;
    }

    // Struct to avoid stack too deep.
    struct LiquidateVars {
        uint256 collateralPrice;
        uint256 borrowBalance;
        uint256 supplyBalance;
        uint256 borrowedPrice;
        uint256 amountToSeize;
        uint256 closeFactor;
        bool liquidationAllowed;
    }

    /// LOGIC ///

    /// @dev Implements supply logic.
    /// @param _poolToken The address of the pool token the user wants to interact with.
    /// @param _from The address of the account sending funds.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function supplyLogic(
        address _poolToken,
        address _from,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_onBehalf == address(0)) revert AddressIsZero();
        if (_amount == 0) revert AmountIsZero();
        if (!marketStatus[_poolToken].isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isSupplyPaused) revert SupplyIsPaused();

        _updateP2PIndexes(_poolToken);
        _enterMarketIfNeeded(_poolToken, _onBehalf);
        ERC20 underlyingToken = _getUnderlying(_poolToken);
        underlyingToken.safeTransferFrom(_from, address(this), _amount);

        Types.Delta storage delta = deltas[_poolToken];
        SupplyVars memory vars;
        vars.poolBorrowIndex = lastPoolIndexes[_poolToken].lastBorrowPoolIndex;
        vars.remainingToSupply = _amount;
        bool p2pDisabled = p2pDisabled[_poolToken];

        /// Peer-to-peer supply ///

        // Match the peer-to-peer borrow delta.
        if (delta.p2pBorrowDelta > 0 && !p2pDisabled) {
            uint256 deltaInUnderlying = delta.p2pBorrowDelta.mul(vars.poolBorrowIndex);
            if (deltaInUnderlying > vars.remainingToSupply) {
                vars.toRepay += vars.remainingToSupply;
                delta.p2pBorrowDelta -= vars.remainingToSupply.div(vars.poolBorrowIndex);
                vars.remainingToSupply = 0;
            } else {
                vars.toRepay += deltaInUnderlying;
                delta.p2pBorrowDelta = 0;
                vars.remainingToSupply -= deltaInUnderlying;
            }
            emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
        }

        // Promote pool borrowers.
        if (
            vars.remainingToSupply > 0 &&
            !p2pDisabled &&
            borrowersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchBorrowers(
                _poolToken,
                vars.remainingToSupply,
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                vars.toRepay += matched;
                vars.remainingToSupply -= matched;
                delta.p2pBorrowAmount += matched.div(p2pBorrowIndex[_poolToken]);
            }
        }

        Types.SupplyBalance storage supplierSupplyBalance = supplyBalanceInOf[_poolToken][
            _onBehalf
        ];

        if (vars.toRepay > 0) {
            uint256 toAddInP2P = vars.toRepay.div(p2pSupplyIndex[_poolToken]);

            delta.p2pSupplyAmount += toAddInP2P;
            supplierSupplyBalance.inP2P += toAddInP2P;
            _repayToPool(_poolToken, underlyingToken, vars.toRepay); // Reverts on error.

            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Pool supply ///

        // Supply on pool.
        if (vars.remainingToSupply > 0) {
            supplierSupplyBalance.onPool += vars.remainingToSupply.div(
                ICToken(_poolToken).exchangeRateStored() // Exchange rate has already been updated.
            ); // In scaled balance.
            _supplyToPool(_poolToken, underlyingToken, vars.remainingToSupply); // Reverts on error.
        }

        _updateSupplierInDS(_poolToken, _onBehalf);

        emit Supplied(
            _from,
            _onBehalf,
            _poolToken,
            _amount,
            supplierSupplyBalance.onPool,
            supplierSupplyBalance.inP2P
        );
    }

    /// @dev Implements borrow logic.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function borrowLogic(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        if (!marketStatus[_poolToken].isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isBorrowPaused) revert BorrowIsPaused();

        _updateP2PIndexes(_poolToken);
        _enterMarketIfNeeded(_poolToken, msg.sender);
        lastBorrowBlock[msg.sender] = block.number;

        if (_isLiquidatable(msg.sender, _poolToken, 0, _amount)) revert UnauthorisedBorrow();
        ERC20 underlyingToken = _getUnderlying(_poolToken);
        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Types.Delta storage delta = deltas[_poolToken];
        uint256 poolSupplyIndex = ICToken(_poolToken).exchangeRateStored(); // Exchange rate has already been updated.
        bool p2pDisabled = p2pDisabled[_poolToken];

        /// Peer-to-peer borrow ///

        // Match the peer-to-peer supply delta.
        if (delta.p2pSupplyDelta > 0 && !p2pDisabled) {
            uint256 deltaInUnderlying = delta.p2pSupplyDelta.mul(poolSupplyIndex);
            if (deltaInUnderlying > remainingToBorrow) {
                toWithdraw += remainingToBorrow;
                delta.p2pSupplyDelta -= remainingToBorrow.div(poolSupplyIndex);
                remainingToBorrow = 0;
            } else {
                toWithdraw += deltaInUnderlying;
                delta.p2pSupplyDelta = 0;
                remainingToBorrow -= deltaInUnderlying;
            }

            emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
        }

        // Promote pool suppliers.
        if (
            remainingToBorrow > 0 &&
            !p2pDisabled &&
            suppliersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchSuppliers(
                _poolToken,
                remainingToBorrow,
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                toWithdraw += matched;
                remainingToBorrow -= matched;
                deltas[_poolToken].p2pSupplyAmount += matched.div(p2pSupplyIndex[_poolToken]);
            }
        }

        Types.BorrowBalance storage borrowerBorrowBalance = borrowBalanceInOf[_poolToken][
            msg.sender
        ];

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.div(p2pBorrowIndex[_poolToken]); // In peer-to-peer unit.

            deltas[_poolToken].p2pBorrowAmount += toAddInP2P;
            borrowerBorrowBalance.inP2P += toAddInP2P;
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            // If this value is equal to 0 the withdraw will revert on Compound.
            if (toWithdraw.div(poolSupplyIndex) > 0) _withdrawFromPool(_poolToken, toWithdraw); // Reverts on error.
        }

        /// Pool borrow ///

        // Borrow on pool.
        if (remainingToBorrow > 0) {
            borrowerBorrowBalance.onPool += remainingToBorrow.div(
                lastPoolIndexes[_poolToken].lastBorrowPoolIndex
            ); // In pool borrow unit.
            _borrowFromPool(_poolToken, remainingToBorrow);
        }

        _updateBorrowerInDS(_poolToken, msg.sender);
        underlyingToken.safeTransfer(msg.sender, _amount);

        emit Borrowed(
            msg.sender,
            _poolToken,
            _amount,
            borrowerBorrowBalance.onPool,
            borrowerBorrowBalance.inP2P
        );
    }

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
        if (!marketStatus[_poolToken].isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isWithdrawPaused) revert WithdrawIsPaused();
        if (!userMembership[_poolToken][_supplier]) revert UserNotMemberOfMarket();

        _updateP2PIndexes(_poolToken);
        uint256 toWithdraw = Math.min(_getUserSupplyBalanceInOf(_poolToken, _supplier), _amount);

        if (_isLiquidatable(_supplier, _poolToken, toWithdraw, 0)) revert UnauthorisedWithdraw();

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
        if (!marketStatus[_poolToken].isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isRepayPaused) revert RepayIsPaused();
        if (!userMembership[_poolToken][_onBehalf]) revert UserNotMemberOfMarket();

        _updateP2PIndexes(_poolToken);
        uint256 toRepay = Math.min(_getUserBorrowBalanceInOf(_poolToken, _onBehalf), _amount);

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
        if (!marketStatus[_poolTokenCollateral].isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolTokenCollateral].isLiquidateCollateralPaused)
            revert LiquidateCollateralIsPaused();
        if (!marketStatus[_poolTokenBorrowed].isCreated) revert MarketNotCreated();
        Types.MarketPauseStatus memory borrowPause = marketPauseStatus[_poolTokenBorrowed];
        if (borrowPause.isLiquidateBorrowPaused) revert LiquidateBorrowIsPaused();
        if (
            !userMembership[_poolTokenBorrowed][_borrower] ||
            !userMembership[_poolTokenCollateral][_borrower]
        ) revert UserNotMemberOfMarket();

        _updateP2PIndexes(_poolTokenBorrowed);
        _updateP2PIndexes(_poolTokenCollateral);

        LiquidateVars memory vars;
        (vars.liquidationAllowed, vars.closeFactor) = _liquidationAllowed(
            _borrower,
            borrowPause.isDeprecated
        );
        if (!vars.liquidationAllowed) revert UnauthorisedLiquidate();

        vars.borrowBalance = _getUserBorrowBalanceInOf(_poolTokenBorrowed, _borrower);

        if (_amount > vars.borrowBalance.mul(vars.closeFactor))
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Compound. Liquidator cannot repay more than part of the debt (cf close factor on Compound).

        _unsafeRepayLogic(_poolTokenBorrowed, msg.sender, _borrower, _amount, 0);

        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());
        vars.collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateral);
        vars.borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowed);
        if (vars.collateralPrice == 0 || vars.borrowedPrice == 0) revert CompoundOracleFailed();

        // Compute the amount of collateral tokens to seize. This is the minimum between the repaid value plus the liquidation incentive and the available supply.
        vars.amountToSeize = Math.min(
            _amount.mul(comptroller.liquidationIncentiveMantissa()).mul(vars.borrowedPrice).div(
                vars.collateralPrice
            ),
            _getUserSupplyBalanceInOf(_poolTokenCollateral, _borrower)
        );

        _unsafeWithdrawLogic(_poolTokenCollateral, vars.amountToSeize, _borrower, msg.sender, 0);

        emit Liquidated(
            msg.sender,
            _borrower,
            _poolTokenBorrowed,
            _amount,
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
        _updateP2PIndexes(_poolToken);

        Types.Delta storage deltas = deltas[_poolToken];
        Types.LastPoolIndexes memory lastPoolIndexes = lastPoolIndexes[_poolToken];

        uint256 poolSupplyIndex = ICToken(_poolToken).exchangeRateStored();
        _amount = Math.min(
            _amount,
            Math.min(
                deltas.p2pSupplyAmount.mul(p2pSupplyIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pSupplyDelta.mul(poolSupplyIndex)
                ),
                deltas.p2pBorrowAmount.mul(p2pBorrowIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pBorrowDelta.mul(lastPoolIndexes.lastBorrowPoolIndex)
                )
            )
        );
        if (_amount == 0) revert AmountIsZero();

        deltas.p2pSupplyDelta += _amount.div(poolSupplyIndex);
        deltas.p2pBorrowDelta += _amount.div(lastPoolIndexes.lastBorrowPoolIndex);
        emit P2PSupplyDeltaUpdated(_poolToken, deltas.p2pSupplyDelta);
        emit P2PBorrowDeltaUpdated(_poolToken, deltas.p2pBorrowDelta);

        _borrowFromPool(_poolToken, _amount);
        _supplyToPool(_poolToken, _getUnderlying(_poolToken), _amount);

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
        WithdrawVars memory vars;
        vars.underlyingToken = _getUnderlying(_poolToken);
        vars.remainingToWithdraw = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolSupplyIndex = ICToken(_poolToken).exchangeRateStored(); // Exchange rate has already been updated.

        if (_amount.div(vars.poolSupplyIndex) == 0) revert WithdrawTooSmall();

        Types.SupplyBalance storage supplierSupplyBalance = supplyBalanceInOf[_poolToken][
            _supplier
        ];

        /// Pool withdraw ///

        // Withdraw supply on pool.
        uint256 onPoolSupply = supplierSupplyBalance.onPool;
        if (onPoolSupply > 0) {
            uint256 maxToWithdrawOnPool = onPoolSupply.mul(vars.poolSupplyIndex);

            if (maxToWithdrawOnPool > vars.remainingToWithdraw) {
                vars.toWithdraw = vars.remainingToWithdraw;
                vars.remainingToWithdraw = 0;
                supplierSupplyBalance.onPool -= vars.toWithdraw.div(vars.poolSupplyIndex);
            } else {
                vars.toWithdraw = maxToWithdrawOnPool;
                vars.remainingToWithdraw -= maxToWithdrawOnPool;
                supplierSupplyBalance.onPool = 0;
            }

            if (vars.remainingToWithdraw == 0) {
                _updateSupplierInDS(_poolToken, _supplier);
                _leaveMarketIfNeeded(_poolToken, _supplier);

                // If this value is equal to 0 the withdraw will revert on Compound.
                if (vars.toWithdraw.div(vars.poolSupplyIndex) > 0)
                    _withdrawFromPool(_poolToken, vars.toWithdraw); // Reverts on error.
                vars.underlyingToken.safeTransfer(_receiver, _amount);

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
            vars.remainingToWithdraw.div(vars.p2pSupplyIndex)
        ); // In peer-to-peer supply unit.
        _updateSupplierInDS(_poolToken, _supplier);

        // Reduce the peer-to-peer supply delta.
        if (vars.remainingToWithdraw > 0 && delta.p2pSupplyDelta > 0) {
            uint256 deltaInUnderlying = delta.p2pSupplyDelta.mul(vars.poolSupplyIndex);

            if (deltaInUnderlying > vars.remainingToWithdraw) {
                delta.p2pSupplyDelta -= vars.remainingToWithdraw.div(vars.poolSupplyIndex);
                delta.p2pSupplyAmount -= vars.remainingToWithdraw.div(vars.p2pSupplyIndex);
                vars.toWithdraw += vars.remainingToWithdraw;
                vars.remainingToWithdraw = 0;
            } else {
                delta.p2pSupplyDelta = 0;
                delta.p2pSupplyAmount -= deltaInUnderlying.div(vars.p2pSupplyIndex);
                vars.toWithdraw += deltaInUnderlying;
                vars.remainingToWithdraw -= deltaInUnderlying;
            }

            emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Transfer withdraw ///

        // Promote pool suppliers.
        if (
            vars.remainingToWithdraw > 0 &&
            !p2pDisabled[_poolToken] &&
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

            if (matched > 0) {
                vars.remainingToWithdraw -= matched;
                vars.toWithdraw += matched;
            }
        }

        // If this value is equal to 0 the withdraw will revert on Compound.
        if (vars.toWithdraw.div(vars.poolSupplyIndex) > 0)
            _withdrawFromPool(_poolToken, vars.toWithdraw); // Reverts on error.

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
                delta.p2pBorrowDelta += (vars.remainingToWithdraw - unmatched).div(
                    lastPoolIndexes[_poolToken].lastBorrowPoolIndex
                );
                emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
            }

            delta.p2pSupplyAmount -= vars.remainingToWithdraw.div(vars.p2pSupplyIndex);
            delta.p2pBorrowAmount -= unmatched.div(p2pBorrowIndex[_poolToken]);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _borrowFromPool(_poolToken, vars.remainingToWithdraw); // Reverts on error.
        }

        _leaveMarketIfNeeded(_poolToken, _supplier);
        vars.underlyingToken.safeTransfer(_receiver, _amount);

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
        if (lastBorrowBlock[_onBehalf] == block.number) revert SameBlockBorrowRepay();

        ERC20 underlyingToken = _getUnderlying(_poolToken);
        underlyingToken.safeTransferFrom(_repayer, address(this), _amount);

        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = lastPoolIndexes[_poolToken].lastBorrowPoolIndex;

        Types.BorrowBalance storage borrowerBorrowBalance = borrowBalanceInOf[_poolToken][
            _onBehalf
        ];

        /// Pool repay ///

        // Repay borrow on pool.
        vars.borrowedOnPool = borrowerBorrowBalance.onPool;
        if (vars.borrowedOnPool > 0) {
            vars.maxToRepayOnPool = vars.borrowedOnPool.mul(vars.poolBorrowIndex);

            if (vars.maxToRepayOnPool > vars.remainingToRepay) {
                vars.toRepay = vars.remainingToRepay;

                borrowerBorrowBalance.onPool -= Math.min(
                    vars.borrowedOnPool,
                    vars.toRepay.div(vars.poolBorrowIndex)
                ); // In pool borrow unit.
                _updateBorrowerInDS(_poolToken, _onBehalf);

                _repayToPool(_poolToken, underlyingToken, vars.toRepay); // Reverts on error.
                _leaveMarketIfNeeded(_poolToken, _onBehalf);

                emit Repaid(
                    _repayer,
                    _onBehalf,
                    _poolToken,
                    _amount,
                    borrowerBorrowBalance.onPool,
                    borrowerBorrowBalance.inP2P
                );

                return;
            } else {
                vars.toRepay = vars.maxToRepayOnPool;
                vars.remainingToRepay -= vars.toRepay;

                borrowerBorrowBalance.onPool = 0;
            }
        }

        Types.Delta storage delta = deltas[_poolToken];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolToken];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolToken];

        borrowerBorrowBalance.inP2P -= Math.min(
            borrowerBorrowBalance.inP2P,
            vars.remainingToRepay.div(vars.p2pBorrowIndex)
        ); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(_poolToken, _onBehalf);

        // Reduce the peer-to-peer borrow delta.
        if (vars.remainingToRepay > 0 && delta.p2pBorrowDelta > 0) {
            uint256 deltaInUnderlying = delta.p2pBorrowDelta.mul(vars.poolBorrowIndex);
            if (deltaInUnderlying > vars.remainingToRepay) {
                delta.p2pBorrowDelta -= vars.remainingToRepay.div(vars.poolBorrowIndex);
                delta.p2pBorrowAmount -= vars.remainingToRepay.div(vars.p2pBorrowIndex);
                vars.toRepay += vars.remainingToRepay;
                vars.remainingToRepay = 0;
            } else {
                delta.p2pBorrowDelta = 0;
                delta.p2pBorrowAmount -= deltaInUnderlying.div(vars.p2pBorrowIndex);
                vars.toRepay += deltaInUnderlying;
                vars.remainingToRepay -= deltaInUnderlying;
            }

            emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        // Repay the fee.
        if (vars.remainingToRepay > 0) {
            // Fee = (p2pBorrowAmount - p2pBorrowDelta) - (p2pSupplyAmount - p2pSupplyDelta).
            // No need to subtract p2pBorrowDelta as it is zero.
            vars.feeToRepay = Math.zeroFloorSub(
                delta.p2pBorrowAmount.mul(vars.p2pBorrowIndex),
                delta.p2pSupplyAmount.mul(vars.p2pSupplyIndex).zeroFloorSub(
                    delta.p2pSupplyDelta.mul(ICToken(_poolToken).exchangeRateStored())
                )
            );

            if (vars.feeToRepay > 0) {
                uint256 feeRepaid = Math.min(vars.feeToRepay, vars.remainingToRepay);
                vars.remainingToRepay -= feeRepaid;
                delta.p2pBorrowAmount -= feeRepaid.div(vars.p2pBorrowIndex);
                emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
            }
        }

        /// Transfer repay ///

        // Promote pool borrowers.
        if (
            vars.remainingToRepay > 0 &&
            !p2pDisabled[_poolToken] &&
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

            if (matched > 0) {
                vars.remainingToRepay -= matched;
                vars.toRepay += matched;
            }
        }

        _repayToPool(_poolToken, underlyingToken, vars.toRepay); // Reverts on error.

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
                delta.p2pSupplyDelta += (vars.remainingToRepay - unmatched).div(
                    ICToken(_poolToken).exchangeRateStored() // Exchange rate has already been updated.
                );
                emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
            }

            delta.p2pSupplyAmount -= unmatched.div(vars.p2pSupplyIndex);
            delta.p2pBorrowAmount -= vars.remainingToRepay.div(vars.p2pBorrowIndex);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _supplyToPool(_poolToken, underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        _leaveMarketIfNeeded(_poolToken, _onBehalf);

        emit Repaid(
            _repayer,
            _onBehalf,
            _poolToken,
            _amount,
            borrowerBorrowBalance.onPool,
            borrowerBorrowBalance.inP2P
        );
    }

    /// @dev Supplies underlying tokens to Compound.
    /// @param _poolToken The address of the pool token.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyToPool(
        address _poolToken,
        ERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        if (_poolToken == cEth) {
            IWETH(wEth).withdraw(_amount); // Turn wETH into ETH.
            ICEther(_poolToken).mint{value: _amount}();
        } else {
            _underlyingToken.safeApprove(_poolToken, _amount);
            uint256 errorCode = ICToken(_poolToken).mint(_amount);
            if (errorCode != 0) revert MintOnCompoundFailed(errorCode);
        }
    }

    /// @dev Withdraws underlying tokens from Compound.
    /// @param _poolToken The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(address _poolToken, uint256 _amount) internal {
        // Withdraw only what is possible. The remaining dust is taken from the contract balance.
        _amount = Math.min(ICToken(_poolToken).balanceOfUnderlying(address(this)), _amount);

        uint256 errorCode = ICToken(_poolToken).redeemUnderlying(_amount);
        if (errorCode != 0) revert RedeemOnCompoundFailed(errorCode);

        if (_poolToken == cEth) IWETH(address(wEth)).deposit{value: _amount}(); // Turn the ETH received in wETH.
    }

    /// @dev Borrows underlying tokens from Compound.
    /// @param _poolToken The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(address _poolToken, uint256 _amount) internal {
        uint256 errorCode = ICToken(_poolToken).borrow(_amount);
        if (errorCode != 0) revert BorrowOnCompoundFailed(errorCode);

        if (_poolToken == cEth) IWETH(address(wEth)).deposit{value: _amount}(); // Turn the ETH received in wETH.
    }

    /// @dev Repays underlying tokens to Compound.
    /// @param _poolToken The address of the pool token.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function _repayToPool(
        address _poolToken,
        ERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
        _amount = Math.min(
            _amount,
            ICToken(_poolToken).borrowBalanceCurrent(address(this)) // The debt of the contract.
        );

        if (_amount > 0) {
            if (_poolToken == cEth) {
                IWETH(wEth).withdraw(_amount); // Turn wETH into ETH.
                ICEther(_poolToken).repayBorrow{value: _amount}();
            } else {
                _underlyingToken.safeApprove(_poolToken, _amount);
                uint256 errorCode = ICToken(_poolToken).repayBorrow(_amount);
                if (errorCode != 0) revert RepayOnCompoundFailed(errorCode);
            }
        }
    }

    /// @dev Enters the user into the market if not already there.
    /// @param _user The address of the user to update.
    /// @param _poolToken The address of the market to check.
    function _enterMarketIfNeeded(address _poolToken, address _user) internal {
        mapping(address => bool) storage userMembership = userMembership[_poolToken];
        if (!userMembership[_user]) {
            userMembership[_user] = true;
            enteredMarkets[_user].push(_poolToken);
        }
    }

    /// @dev Removes the user from the market if its balances are null.
    /// @param _user The address of the user to update.
    /// @param _poolToken The address of the market to check.
    function _leaveMarketIfNeeded(address _poolToken, address _user) internal {
        Types.SupplyBalance storage supplyBalance = supplyBalanceInOf[_poolToken][_user];
        Types.BorrowBalance storage borrowBalance = borrowBalanceInOf[_poolToken][_user];
        mapping(address => bool) storage userMembership = userMembership[_poolToken];
        if (
            userMembership[_user] &&
            supplyBalance.inP2P == 0 &&
            supplyBalance.onPool == 0 &&
            borrowBalance.inP2P == 0 &&
            borrowBalance.onPool == 0
        ) {
            address[] storage enteredMarkets = enteredMarkets[_user];
            uint256 index;
            while (enteredMarkets[index] != _poolToken) {
                unchecked {
                    ++index;
                }
            }

            userMembership[_user] = false;

            uint256 length = enteredMarkets.length;
            if (index != length - 1) enteredMarkets[index] = enteredMarkets[length - 1];
            enteredMarkets.pop();
        }
    }

    /// @dev Returns whether a given user is liquidatable and the applicable close factor, given the deprecated status of the borrowed market.
    /// @param _user The user to check.
    /// @param _isDeprecated Whether the borrowed market is deprecated or not.
    /// @return liquidationAllowed Whether the liquidation is allowed or not.
    /// @return closeFactor The close factor to apply.
    function _liquidationAllowed(address _user, bool _isDeprecated)
        internal
        view
        returns (bool liquidationAllowed, uint256 closeFactor)
    {
        if (_isDeprecated) {
            liquidationAllowed = true;
            closeFactor = WAD; // Allow liquidation of the whole debt.
        } else {
            liquidationAllowed = _isLiquidatable(_user, address(0), 0, 0);
            if (liquidationAllowed) closeFactor = comptroller.closeFactorMantissa();
        }
    }
}
