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
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external override {
        if (
            !userMembership[_poolTokenBorrowedAddress][_borrower] ||
            !userMembership[_poolTokenCollateralAddress][_borrower]
        ) revert UserNotMemberOfMarket();

        _updateP2PIndexes(_poolTokenBorrowedAddress);
        _updateP2PIndexes(_poolTokenCollateralAddress);

        if (!_isLiquidatable(_borrower, address(0), 0, 0)) revert UnauthorisedLiquidate();

        LiquidateVars memory vars;
        vars.borrowBalance = _getUserBorrowBalanceInOf(_poolTokenBorrowedAddress, _borrower);

        if (_amount > vars.borrowBalance.mul(comptroller.closeFactorMantissa()))
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Compound. Liquidator cannot repay more than part of the debt (cf close factor on Compound).

        if (isTransfer) {
            _transferSafeRepayLogic(_poolTokenBorrowedAddress, msg.sender, _borrower, _amount, 0);
        } else {
            _hardSafeRepayLogic(_poolTokenBorrowedAddress, msg.sender, _borrower, _amount, 0);
        }

        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());
        vars.collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateralAddress);
        vars.borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
        if (vars.collateralPrice == 0 || vars.borrowedPrice == 0) revert CompoundOracleFailed();

        // Compute the amount of collateral tokens to seize. This is the minimum between the repaid value plus the liquidation incentive and the available supply.
        vars.amountToSeize = Math.min(
            _amount.mul(comptroller.liquidationIncentiveMantissa()).mul(vars.borrowedPrice).div(
                vars.collateralPrice
            ),
            _getUserSupplyBalanceInOf(_poolTokenCollateralAddress, _borrower)
        );
        if (isTransfer) {
            _transferSafeWithdrawLogic(
                _poolTokenCollateralAddress,
                vars.amountToSeize,
                _borrower,
                msg.sender,
                0
            );
        } else {
            _hardSafeWithdrawLogic(
                _poolTokenCollateralAddress,
                vars.amountToSeize,
                _borrower,
                msg.sender,
                0
            );
        }

        emit Liquidated(
            msg.sender,
            _borrower,
            _poolTokenBorrowedAddress,
            _amount,
            _poolTokenCollateralAddress,
            vars.amountToSeize
        );
    }

    function _transferSafeRepayLogic(
        address _poolTokenAddress,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        if (lastBorrowBlock[_onBehalf] == block.number) revert SameBlockBorrowRepay();

        ERC20 underlyingToken = _getUnderlying(_poolTokenAddress);
        underlyingToken.safeTransferFrom(_repayer, address(this), _amount);

        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = ICToken(_poolTokenAddress).borrowIndex();

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolTokenAddress];

        borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P -= CompoundMath.min(
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P,
            vars.remainingToRepay.div(vars.p2pBorrowIndex)
        ); // In peer-to-peer unit.
        _updateBorrowerInDS(_poolTokenAddress, _onBehalf);

        /// Transfer repay ///

        // Reduce peer-to-peer borrow delta first if any.
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

            emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        // Repay the fee.
        if (vars.remainingToRepay > 0) {
            // Fee = (p2pBorrowAmount - p2pBorrowDelta) - (p2pSupplyAmount - p2pSupplyDelta).
            vars.feeToRepay = CompoundMath.safeSub(
                (delta.p2pBorrowAmount.mul(vars.p2pBorrowIndex) -
                    delta.p2pBorrowDelta.mul(vars.poolBorrowIndex)),
                (delta.p2pSupplyAmount.mul(vars.p2pSupplyIndex) -
                    delta.p2pSupplyDelta.mul(ICToken(_poolTokenAddress).exchangeRateStored()))
            );

            if (vars.feeToRepay > 0) {
                uint256 feeRepaid = CompoundMath.min(vars.feeToRepay, vars.remainingToRepay);
                vars.remainingToRepay -= feeRepaid;
                delta.p2pBorrowAmount -= feeRepaid.div(vars.p2pBorrowIndex);
                emit P2PAmountsUpdated(
                    _poolTokenAddress,
                    delta.p2pSupplyAmount,
                    delta.p2pBorrowAmount
                );
            }
        }

        // Match pool borrowers if any.
        if (
            vars.remainingToRepay > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            borrowersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            (uint256 matched, uint256 gasConsumedInMatching) = _matchBorrowers(
                _poolTokenAddress,
                vars.remainingToRepay,
                vars.maxGasForMatching
            );
            if (vars.maxGasForMatching <= gasConsumedInMatching) vars.maxGasForMatching = 0;
            else vars.maxGasForMatching -= gasConsumedInMatching;

            if (matched > 0) {
                vars.remainingToRepay -= matched;
                vars.toRepay += matched;
            }
        }

        _repayToPool(_poolTokenAddress, underlyingToken, vars.toRepay); // Reverts on error.
    }

    function _hardSafeRepayLogic(
        address _poolTokenAddress,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        if (lastBorrowBlock[_onBehalf] == block.number) revert SameBlockBorrowRepay();

        ERC20 underlyingToken = _getUnderlying(_poolTokenAddress);
        underlyingToken.safeTransferFrom(_repayer, address(this), _amount);

        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = ICToken(_poolTokenAddress).borrowIndex();

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolTokenAddress];

        borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P -= CompoundMath.min(
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P,
            vars.remainingToRepay.div(vars.p2pBorrowIndex)
        ); // In peer-to-peer unit.
        _updateBorrowerInDS(_poolTokenAddress, _onBehalf);
        // Unmatch peer-to-peer suppliers.
        if (vars.remainingToRepay > 0) {
            uint256 unmatched = _unmatchSuppliers(
                _poolTokenAddress,
                vars.remainingToRepay,
                vars.maxGasForMatching
            );

            // If unmatched does not cover remainingToRepay, the difference is added to the supply peer-to-peer delta.
            if (unmatched < vars.remainingToRepay) {
                delta.p2pSupplyDelta += (vars.remainingToRepay - unmatched).div(
                    ICToken(_poolTokenAddress).exchangeRateStored() // Exchange rate has already been updated.
                );
                emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
            }

            delta.p2pSupplyAmount -= unmatched.div(vars.p2pSupplyIndex);
            delta.p2pBorrowAmount -= vars.remainingToRepay.div(vars.p2pBorrowIndex);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _supplyToPool(_poolTokenAddress, underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        _leaveMarketIfNeeded(_poolTokenAddress, _onBehalf);

        emit Repaid(
            _repayer,
            _onBehalf,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].onPool,
            borrowBalanceInOf[_poolTokenAddress][_onBehalf].inP2P
        );
    }

    function _transferSafeWithdrawLogic(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) internal {
        if (_amount == 0) revert AmountIsZero();

        WithdrawVars memory vars;
        vars.poolToken = ICToken(_poolTokenAddress);
        vars.underlyingToken = _getUnderlying(_poolTokenAddress);
        vars.remainingToWithdraw = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.withdrawable = vars.poolToken.balanceOfUnderlying(address(this));
        vars.poolSupplyIndex = vars.poolToken.exchangeRateStored(); // Exchange rate has already been updated.

        if (_amount.div(vars.poolSupplyIndex) == 0) revert WithdrawTooSmall();

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];

        supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= CompoundMath.min(
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
            vars.remainingToWithdraw.div(vars.p2pSupplyIndex)
        ); // In peer-to-peer unit
        _updateSupplierInDS(_poolTokenAddress, _supplier);

        // / Transfer withdraw ///

        // Reduce peer-to-peer supply delta first if any.
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
                CompoundMath.min(vars.remainingToWithdraw, vars.withdrawable - vars.toWithdraw),
                vars.maxGasForMatching
            );
            if (vars.maxGasForMatching <= gasConsumedInMatching) vars.maxGasForMatching = 0;
            else vars.maxGasForMatching -= gasConsumedInMatching;

            if (matched > 0) {
                vars.remainingToWithdraw -= matched;
                vars.toWithdraw += matched;
            }
        }

        // If this value is equal to 0 the withdraw will revert on Compound.
        if (vars.toWithdraw.div(vars.poolSupplyIndex) > 0)
            _withdrawFromPool(_poolTokenAddress, vars.toWithdraw); // Reverts on error.
    }

    function _hardSafeWithdrawLogic(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) internal {
        if (_amount == 0) revert AmountIsZero();

        WithdrawVars memory vars;
        vars.poolToken = ICToken(_poolTokenAddress);
        vars.underlyingToken = _getUnderlying(_poolTokenAddress);
        vars.remainingToWithdraw = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.withdrawable = vars.poolToken.balanceOfUnderlying(address(this));
        vars.poolSupplyIndex = vars.poolToken.exchangeRateStored(); // Exchange rate has already been updated.

        if (_amount.div(vars.poolSupplyIndex) == 0) revert WithdrawTooSmall();

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];

        supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= CompoundMath.min(
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
            vars.remainingToWithdraw.div(vars.p2pSupplyIndex)
        ); // In peer-to-peer unit
        _updateSupplierInDS(_poolTokenAddress, _supplier);

        // Reduce peer-to-peer supply delta first if any.
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

            emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pSupplyDelta);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Hard withdraw ///

        // Unmatch peer-to-peer borrowers.
        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = _unmatchBorrowers(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                _maxGasForMatching
            );

            // If unmatched does not cover remainingToWithdraw, the difference is added to the borrow peer-to-peer delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.p2pBorrowDelta += (vars.remainingToWithdraw - unmatched).div(
                    vars.poolToken.borrowIndex()
                );
                emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowAmount);
            }

            delta.p2pSupplyAmount -= vars.remainingToWithdraw.div(vars.p2pSupplyIndex);
            delta.p2pBorrowAmount -= unmatched.div(p2pBorrowIndex[_poolTokenAddress]);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _borrowFromPool(_poolTokenAddress, vars.remainingToWithdraw); // Reverts on error.
        }

        _leaveMarketIfNeeded(_poolTokenAddress, _supplier);
        vars.underlyingToken.safeTransfer(_receiver, _amount);

        emit Withdrawn(
            _supplier,
            _receiver,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool,
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P
        );
    }
}
