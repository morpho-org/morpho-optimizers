// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

// This is the contract that is actually verified; it may contain some helper
// methods for the spec to access internal state, or may override some of the
// more complex methods in the original contract.

import "../../munged/compound/PositionsManager.sol";

contract PositionsManagerHarness is PositionsManager {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    // constructor(address _compoundMarketsManager, address _proxyComptrollerAddress)
    //     PositionsManager(_compoundMarketsManager, _proxyComptrollerAddress)
    // {} // previous constructor, kept for reference

    constructor() {}

    bool public isTransfer; // transfer vs hard for repay/withdraw

    function liquidateLogic(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external override {
        if (
            !userMembership[_poolTokenBorrowed][_borrower] ||
            !userMembership[_poolTokenCollateral][_borrower]
        ) revert UserNotMemberOfMarket();

        _updateP2PIndexes(_poolTokenBorrowed);
        _updateP2PIndexes(_poolTokenCollateral);

        if (!_isLiquidatable(_borrower, address(0), 0, 0)) revert UnauthorisedLiquidate();

        LiquidateVars memory vars;
        vars.borrowBalance = _getUserBorrowBalanceInOf(_poolTokenBorrowed, _borrower);

        if (_amount > vars.borrowBalance.mul(comptroller.closeFactorMantissa()))
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Compound. Liquidator cannot repay more than part of the debt (cf close factor on Compound).

        _noMatchingSafeRepayLogic(_poolTokenBorrowed, msg.sender, _borrower, _amount, 0);

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

        noMatchingSafeWithdrawLogic(
            _poolTokenCollateral,
            vars.amountToSeize,
            _borrower,
            msg.sender,
            0
        );

        emit Liquidated(
            msg.sender,
            _borrower,
            _poolTokenBorrowed,
            _amount,
            _poolTokenCollateral,
            vars.amountToSeize
        );
    }

    function _noMatchingSafeRepayLogic(
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
        vars.poolBorrowIndex = ICToken(_poolToken).borrowIndex();

        /// Pool repay ///

        // Repay borrow on pool.
        vars.borrowedOnPool = borrowBalanceInOf[_poolToken][_onBehalf].onPool;
        if (vars.borrowedOnPool > 0) {
            vars.maxToRepayOnPool = vars.borrowedOnPool.mul(vars.poolBorrowIndex);

            if (vars.maxToRepayOnPool > vars.remainingToRepay) {
                vars.toRepay = vars.remainingToRepay;

                borrowBalanceInOf[_poolToken][_onBehalf].onPool -= CompoundMath.min(
                    vars.borrowedOnPool,
                    vars.toRepay.div(vars.poolBorrowIndex)
                ); // In cdUnit.
                _updateBorrowerInDS(_poolToken, _onBehalf);

                _repayToPool(_poolToken, underlyingToken, vars.toRepay); // Reverts on error.
                _leaveMarketIfNeeded(_poolToken, _onBehalf);

                emit Repaid(
                    _repayer,
                    _onBehalf,
                    _poolToken,
                    _amount,
                    borrowBalanceInOf[_poolToken][_onBehalf].onPool,
                    borrowBalanceInOf[_poolToken][_onBehalf].inP2P
                );

                return;
            } else {
                vars.toRepay = vars.maxToRepayOnPool;
                vars.remainingToRepay -= vars.toRepay;

                borrowBalanceInOf[_poolToken][_onBehalf].onPool = 0;
            }
        }

        Types.Delta storage delta = deltas[_poolToken];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolToken];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolToken];

        borrowBalanceInOf[_poolToken][_onBehalf].inP2P -= CompoundMath.min(
            borrowBalanceInOf[_poolToken][_onBehalf].inP2P,
            vars.remainingToRepay.div(vars.p2pBorrowIndex)
        ); // In peer-to-peer unit.
        _updateBorrowerInDS(_poolToken, _onBehalf);

        // Reduce peer-to-peer borrow delta.
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
            vars.feeToRepay = CompoundMath.safeSub(
                delta.p2pBorrowAmount.mul(vars.p2pBorrowIndex),
                (delta.p2pSupplyAmount.mul(vars.p2pSupplyIndex) -
                    delta.p2pSupplyDelta.mul(ICToken(_poolToken).exchangeRateStored()))
            );

            if (vars.feeToRepay > 0) {
                uint256 feeRepaid = CompoundMath.min(vars.feeToRepay, vars.remainingToRepay);
                vars.remainingToRepay -= feeRepaid;
                delta.p2pBorrowAmount -= feeRepaid.div(vars.p2pBorrowIndex);
                emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
            }
        }

        // HARNESS: removed promote borrowers

        _repayToPool(_poolToken, underlyingToken, vars.toRepay); // Reverts on error.

        /// Breaking repay ///

        if (vars.remainingToRepay > 0) {
            // HARNESS: removed demote suppliers
            // Increase the peer-to-peer supply delta.
            delta.p2pSupplyDelta += vars.remainingToRepay.div(
                ICToken(_poolToken).exchangeRateStored() // Exchange rate has already been updated.
            );
            emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);

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
            borrowBalanceInOf[_poolToken][_onBehalf].onPool,
            borrowBalanceInOf[_poolToken][_onBehalf].inP2P
        );
    }

    function _noMatchingSafeWithdrawLogic(
        address _poolToken,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) internal {
        if (_amount == 0) revert AmountIsZero();

        WithdrawVars memory vars;
        vars.underlyingToken = _getUnderlying(_poolToken);
        vars.remainingToWithdraw = _amount;
        vars.remainingGasForMatching = _maxGasForMatching;
        vars.withdrawable = ICToken(_poolToken).balanceOfUnderlying(address(this));
        vars.poolSupplyIndex = ICToken(_poolToken).exchangeRateStored(); // Exchange rate has already been updated.

        if (_amount.div(vars.poolSupplyIndex) == 0) revert WithdrawTooSmall();

        /// Pool withdraw ///

        // Withdraw supply on pool.
        uint256 onPoolSupply = supplyBalanceInOf[_poolToken][_supplier].onPool;
        if (onPoolSupply > 0) {
            uint256 maxToWithdrawOnPool = onPoolSupply.mul(vars.poolSupplyIndex);

            if (
                maxToWithdrawOnPool > vars.remainingToWithdraw ||
                maxToWithdrawOnPool > vars.withdrawable
            ) {
                vars.toWithdraw = CompoundMath.min(vars.remainingToWithdraw, vars.withdrawable);

                vars.remainingToWithdraw -= vars.toWithdraw;
                supplyBalanceInOf[_poolToken][_supplier].onPool -= vars.toWithdraw.div(
                    vars.poolSupplyIndex
                );
            } else {
                vars.toWithdraw = maxToWithdrawOnPool;
                vars.remainingToWithdraw -= maxToWithdrawOnPool;
                supplyBalanceInOf[_poolToken][_supplier].onPool = 0;
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
                    supplyBalanceInOf[_poolToken][_supplier].onPool,
                    supplyBalanceInOf[_poolToken][_supplier].inP2P
                );

                return;
            }
        }

        Types.Delta storage delta = deltas[_poolToken];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolToken];

        supplyBalanceInOf[_poolToken][_supplier].inP2P -= CompoundMath.min(
            supplyBalanceInOf[_poolToken][_supplier].inP2P,
            vars.remainingToWithdraw.div(vars.p2pSupplyIndex)
        ); // In peer-to-peer unit
        _updateSupplierInDS(_poolToken, _supplier);

        // Reduce peer-to-peer supply delta.
        if (vars.remainingToWithdraw > 0 && delta.p2pSupplyDelta > 0) {
            uint256 deltaInUnderlying = delta.p2pSupplyDelta.mul(vars.poolSupplyIndex);

            if (
                deltaInUnderlying > vars.remainingToWithdraw ||
                deltaInUnderlying > vars.withdrawable - vars.toWithdraw
            ) {
                uint256 matchedDelta = CompoundMath.min(
                    vars.remainingToWithdraw,
                    vars.withdrawable - vars.toWithdraw
                );

                delta.p2pSupplyDelta -= matchedDelta.div(vars.poolSupplyIndex);
                delta.p2pSupplyAmount -= matchedDelta.div(vars.p2pSupplyIndex);
                vars.toWithdraw += matchedDelta;
                vars.remainingToWithdraw -= matchedDelta;
            } else {
                vars.toWithdraw += deltaInUnderlying;
                vars.remainingToWithdraw -= deltaInUnderlying;
                delta.p2pSupplyDelta = 0;
                delta.p2pSupplyAmount -= deltaInUnderlying.div(vars.p2pSupplyIndex);
            }

            emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        // HARNESS: removed promote suppliers

        // If this value is equal to 0 the withdraw will revert on Compound.
        if (vars.toWithdraw.div(vars.poolSupplyIndex) > 0)
            _withdrawFromPool(_poolToken, vars.toWithdraw); // Reverts on error.

        /// Breaking withdraw ///

        if (vars.remainingToWithdraw > 0) {
            // HARNESS: removed demote borrowers
            // Increase the peer-to-peer borrow delta.
            delta.p2pBorrowDelta += vars.remainingToWithdraw.div(ICToken(_poolToken).borrowIndex());
            emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);

            delta.p2pSupplyAmount -= vars.remainingToWithdraw.div(vars.p2pSupplyIndex);
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
            supplyBalanceInOf[_poolToken][_supplier].onPool,
            supplyBalanceInOf[_poolToken][_supplier].inP2P
        );
    }
}
