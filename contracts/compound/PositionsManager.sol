// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IPositionsManager.sol";
import "./interfaces/IWETH.sol";

import "./MatchingEngine.sol";

/// @title PositionsManager.
/// @notice Main Logic of Morpho Protocol, implementation of the 5 main functionalities: supply, borrow, withdraw, repay and liquidate.
contract PositionsManager is IPositionsManager, MatchingEngine {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// EVENTS ///

    /// @notice Emitted when a supply happens.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Supplied(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a borrow happens.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update
    event Borrowed(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a withdrawal happens.
    /// @param _user The address of the withdrawer.
    /// @param _poolTokenAddress The address of the market from where assets are withdrawn.
    /// @param _amount The amount of assets withdrawn (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Withdrawn(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a repayment happens.
    /// @param _user The address of the repayer.
    /// @param _poolTokenAddress The address of the market where assets are repaid.
    /// @param _amount The amount of assets repaid (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event Repaid(
        address indexed _user,
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

    /// @notice Emitted when the borrow peer-to-peer delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pBorrowDelta The borrow peer-to-peer delta after update.
    event P2PBorrowDeltaUpdated(address indexed _poolTokenAddress, uint256 _p2pBorrowDelta);

    /// @notice Emitted when the supply peer-to-peer delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pSupplyDelta The supply peer-to-peer delta after update.
    event P2PSupplyDeltaUpdated(address indexed _poolTokenAddress, uint256 _p2pSupplyDelta);

    /// @notice Emitted when the supply and borrow peer-to-peer amounts are updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pSupplyAmount The supply peer-to-peer amount after update.
    /// @param _p2pBorrowAmount The borrow peer-to-peer amount after update.
    event P2PAmountsUpdated(
        address indexed _poolTokenAddress,
        uint256 _p2pSupplyAmount,
        uint256 _p2pBorrowAmount
    );

    /// ERRORS ///

    /// @notice Thrown when the amount repaid during the liquidation is above what is allowed to be repaid.
    error AmountAboveWhatAllowedToRepay();

    /// @notice Thrown when the amount of collateral to seize is above the collateral amount.
    error ToSeizeAboveCollateral();

    /// @notice Thrown when the borrow on Compound failed.
    error BorrowOnCompoundFailed();

    /// @notice Thrown when the redeem on Compound failed .
    error RedeemOnCompoundFailed();

    /// @notice Thrown when the repay on Compound failed.
    error RepayOnCompoundFailed();

    /// @notice Thrown when the mint on Compound failed.
    error MintOnCompoundFailed();

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

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct WithdrawVars {
        uint256 remainingToWithdraw;
        uint256 maxGasForMatching;
        uint256 poolSupplyIndex;
        uint256 p2pSupplyIndex;
        uint256 withdrawable;
        uint256 toWithdraw;
        ERC20 underlyingToken;
        ICToken poolToken;
    }

    // Struct to avoid stack too deep.
    struct RepayVars {
        uint256 maxGasForMatching;
        uint256 remainingToRepay;
        uint256 poolBorrowIndex;
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
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
        uint256 maxDebtValue;
        uint256 debtValue;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the PositionsManager contract.
    /// @dev The contract is automatically marked as initialized when deployed.
    constructor() initializer {}

    /// LOGIC ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function supplyLogic(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        _updateP2PIndexes(_poolTokenAddress);

        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        ERC20 underlyingToken = _getUnderlying(_poolTokenAddress);
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolBorrowIndex = ICToken(_poolTokenAddress).borrowIndex();
        uint256 remainingToSupply = _amount;
        uint256 toRepay;

        /// Supply in peer-to-peer ///

        // Match borrow peer-to-peer delta first if any.
        if (delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = CompoundMath.min(
                delta.p2pBorrowDelta.mul(poolBorrowIndex),
                remainingToSupply
            );

            toRepay += matchedDelta;
            remainingToSupply -= matchedDelta;
            delta.p2pBorrowDelta -= matchedDelta.div(poolBorrowIndex);
            emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
        }

        // Match pool borrowers if any.
        if (
            remainingToSupply > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            borrowersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchBorrowers(
                _poolTokenAddress,
                remainingToSupply,
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                toRepay += matched;
                remainingToSupply -= matched;
                delta.p2pBorrowAmount += matched.div(p2pBorrowIndex[_poolTokenAddress]);
            }
        }

        if (toRepay > 0) {
            uint256 toAddInP2P = toRepay.div(p2pSupplyIndex[_poolTokenAddress]);

            delta.p2pSupplyAmount += toAddInP2P;
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;

            // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
            toRepay = Math.min(
                toRepay,
                ICToken(_poolTokenAddress).borrowBalanceCurrent(address(this)) // The debt of the contract.
            );

            _repayToPool(_poolTokenAddress, underlyingToken, toRepay); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Supply on pool ///

        if (remainingToSupply > 0) {
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupply.div(
                ICToken(_poolTokenAddress).exchangeRateStored() // Exchange rate has already been updated.
            ); // In scaled balance.
            _supplyToPool(_poolTokenAddress, underlyingToken, remainingToSupply); // Reverts on error.
        }

        _updateSupplierInDS(_poolTokenAddress, msg.sender);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function borrowLogic(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        _updateP2PIndexes(_poolTokenAddress);

        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        if (_isLiquidatable(msg.sender, _poolTokenAddress, 0, _amount)) revert UnauthorisedBorrow();
        ERC20 underlyingToken = _getUnderlying(_poolTokenAddress);
        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolSupplyIndex = ICToken(_poolTokenAddress).exchangeRateStored(); // Exchange rate has already been updated.
        uint256 withdrawable = ICToken(_poolTokenAddress).balanceOfUnderlying(address(this)); // The balance on pool.

        /// Borrow in peer-to-peer ///

        // Match supply peer-to-peer delta first if any.
        if (delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = CompoundMath.min(
                delta.p2pSupplyDelta.mul(poolSupplyIndex),
                remainingToBorrow,
                withdrawable
            );

            toWithdraw += matchedDelta;
            remainingToBorrow -= matchedDelta;
            delta.p2pSupplyDelta -= matchedDelta.div(poolSupplyIndex);
            emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pSupplyDelta);
        }

        // Match pool suppliers if any.
        if (
            remainingToBorrow > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            suppliersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchSuppliers(
                _poolTokenAddress,
                CompoundMath.min(remainingToBorrow, withdrawable - toWithdraw),
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                toWithdraw += matched;
                remainingToBorrow -= matched;
                deltas[_poolTokenAddress].p2pSupplyAmount += matched.div(
                    p2pSupplyIndex[_poolTokenAddress]
                );
            }
        }

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.div(p2pBorrowIndex[_poolTokenAddress]); // In peer-to-peer unit.

            deltas[_poolTokenAddress].p2pBorrowAmount += toAddInP2P;
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            // If this value is equal to 0 the withdraw will revert on Compound.
            if (toWithdraw.div(poolSupplyIndex) > 0)
                _withdrawFromPool(_poolTokenAddress, toWithdraw); // Reverts on error.
        }

        /// Borrow on pool ///

        if (remainingToBorrow > 0) {
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrow.div(
                ICToken(_poolTokenAddress).borrowIndex()
            ); // In cdUnit.
            _borrowFromPool(_poolTokenAddress, remainingToBorrow);
        }

        _updateBorrowerInDS(_poolTokenAddress, msg.sender);
        underlyingToken.safeTransfer(msg.sender, _amount);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

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
        if (!userMembership[_poolTokenAddress][_supplier]) revert UserNotMemberOfMarket();

        _updateP2PIndexes(_poolTokenAddress);
        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(_poolTokenAddress, _supplier),
            _amount
        );

        if (_isLiquidatable(_supplier, _poolTokenAddress, toWithdraw, 0))
            revert UnauthorisedWithdraw();

        _safeWithdrawLogic(_poolTokenAddress, toWithdraw, _supplier, _receiver, _maxGasForMatching);
    }

    /// @dev Implements repay logic with security checks.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function repayLogic(
        address _poolTokenAddress,
        address _user,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        if (!userMembership[_poolTokenAddress][_user]) revert UserNotMemberOfMarket();

        _updateP2PIndexes(_poolTokenAddress);
        uint256 toRepay = Math.min(_getUserBorrowBalanceInOf(_poolTokenAddress, _user), _amount);

        _safeRepayLogic(_poolTokenAddress, _user, toRepay, _maxGasForMatching);
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

        _safeRepayLogic(_poolTokenBorrowedAddress, _borrower, _amount, 0);

        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());
        vars.collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateralAddress);
        vars.borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
        if (vars.collateralPrice == 0 || vars.borrowedPrice == 0) revert CompoundOracleFailed();

        // Compute the amount of collateral tokens to seize (Same mechanism as Compound).
        vars.amountToSeize = _amount
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(vars.borrowedPrice)
        .div(vars.collateralPrice);

        vars.supplyBalance = _getUserSupplyBalanceInOf(_poolTokenCollateralAddress, _borrower);

        if (vars.amountToSeize > vars.supplyBalance) revert ToSeizeAboveCollateral();

        _safeWithdrawLogic(
            _poolTokenCollateralAddress,
            vars.amountToSeize,
            _borrower,
            msg.sender,
            0
        );

        emit Liquidated(
            msg.sender,
            _borrower,
            _poolTokenBorrowedAddress,
            _amount,
            _poolTokenCollateralAddress,
            vars.amountToSeize
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
        if (_amount == 0) revert AmountIsZero();

        WithdrawVars memory vars;
        vars.poolToken = ICToken(_poolTokenAddress);
        vars.underlyingToken = _getUnderlying(_poolTokenAddress);
        vars.remainingToWithdraw = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.withdrawable = vars.poolToken.balanceOfUnderlying(address(this));
        vars.poolSupplyIndex = vars.poolToken.exchangeRateStored(); // Exchange rate has already been updated.

        if (_amount.div(vars.poolSupplyIndex) == 0) revert WithdrawTooSmall();

        /// Soft withdraw ///

        uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
        if (onPoolSupply > 0) {
            vars.toWithdraw = CompoundMath.min(
                onPoolSupply.mul(vars.poolSupplyIndex),
                vars.remainingToWithdraw,
                vars.withdrawable
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= CompoundMath.min(
                onPoolSupply,
                vars.toWithdraw.div(vars.poolSupplyIndex)
            );
            _updateSupplierInDS(_poolTokenAddress, _supplier);

            if (vars.remainingToWithdraw == 0) {
                _leaveMarketIfNeeded(_poolTokenAddress, _supplier);
                // If this value is equal to 0 the withdraw will revert on Compound.
                if (vars.toWithdraw.div(vars.poolSupplyIndex) > 0)
                    _withdrawFromPool(_poolTokenAddress, vars.toWithdraw); // Reverts on error.
                vars.underlyingToken.safeTransfer(_receiver, _amount);
                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];

        supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= CompoundMath.min(
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
            vars.remainingToWithdraw.div(vars.p2pSupplyIndex)
        ); // In peer-to-peer unit
        _updateSupplierInDS(_poolTokenAddress, _supplier);

        /// Transfer withdraw ///

        // Match peer-to-peer supply delta first if any.
        if (vars.remainingToWithdraw > 0 && delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = CompoundMath.min(
                delta.p2pSupplyDelta.mul(vars.poolSupplyIndex),
                vars.remainingToWithdraw,
                vars.withdrawable - vars.toWithdraw
            );

            vars.toWithdraw += matchedDelta;
            vars.remainingToWithdraw -= matchedDelta;
            delta.p2pSupplyDelta -= matchedDelta.div(vars.poolSupplyIndex);
            delta.p2pSupplyAmount -= matchedDelta.div(vars.p2pSupplyIndex);
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

        /// Hard withdraw ///

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
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool,
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P
        );
    }

    /// @dev Implements repay logic without security checks.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function _safeRepayLogic(
        address _poolTokenAddress,
        address _user,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal {
        ICToken poolToken = ICToken(_poolTokenAddress);
        ERC20 underlyingToken = _getUnderlying(_poolTokenAddress);
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = poolToken.borrowIndex();

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            vars.toRepay = CompoundMath.min(
                borrowedOnPool.mul(vars.poolBorrowIndex),
                vars.remainingToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= CompoundMath.min(
                borrowedOnPool,
                vars.toRepay.div(vars.poolBorrowIndex)
            ); // In cdUnit.
            _updateBorrowerInDS(_poolTokenAddress, _user);

            if (vars.remainingToRepay == 0) {
                _repayToPool(_poolTokenAddress, underlyingToken, vars.toRepay); // Reverts on error.
                _leaveMarketIfNeeded(_poolTokenAddress, _user);
                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];
        vars.p2pBorrowIndex = p2pBorrowIndex[_poolTokenAddress];

        borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= CompoundMath.min(
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P,
            vars.remainingToRepay.div(vars.p2pBorrowIndex)
        ); // In peer-to-peer unit.
        _updateBorrowerInDS(_poolTokenAddress, _user);

        /// Transfer repay ///

        // Match peer-to-peer borrow delta first if any.
        if (vars.remainingToRepay > 0 && delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = CompoundMath.min(
                delta.p2pBorrowDelta.mul(vars.poolBorrowIndex),
                vars.remainingToRepay
            );

            vars.toRepay += matchedDelta;
            vars.remainingToRepay -= matchedDelta;
            delta.p2pBorrowDelta -= matchedDelta.div(vars.poolBorrowIndex);
            delta.p2pBorrowAmount -= matchedDelta.div(vars.p2pBorrowIndex);
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
                    delta.p2pSupplyDelta.mul(poolToken.exchangeRateStored()))
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

        /// Hard repay ///

        if (vars.remainingToRepay > 0) {
            uint256 unmatched = _unmatchSuppliers(
                _poolTokenAddress,
                vars.remainingToRepay,
                vars.maxGasForMatching
            );

            // If unmatched does not cover remainingToRepay, the difference is added to the supply peer-to-peer delta.
            if (unmatched < vars.remainingToRepay) {
                delta.p2pSupplyDelta += (vars.remainingToRepay - unmatched).div(
                    poolToken.exchangeRateStored() // Exchange rate has already been updated.
                );
                emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
            }

            delta.p2pSupplyAmount -= unmatched.div(vars.p2pSupplyIndex);
            delta.p2pBorrowAmount -= vars.remainingToRepay.div(vars.p2pBorrowIndex);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _supplyToPool(_poolTokenAddress, underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        _leaveMarketIfNeeded(_poolTokenAddress, _user);

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
    }

    /// @dev Supplies underlying tokens to Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyToPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        if (_poolTokenAddress == cEth) {
            IWETH(wEth).withdraw(_amount); // Turn wETH into ETH.
            ICEther(_poolTokenAddress).mint{value: _amount}();
        } else {
            _underlyingToken.safeApprove(_poolTokenAddress, _amount);
            if (ICToken(_poolTokenAddress).mint(_amount) != 0) revert MintOnCompoundFailed();
        }
    }

    /// @dev Withdraws underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(address _poolTokenAddress, uint256 _amount) internal {
        if (ICToken(_poolTokenAddress).redeemUnderlying(_amount) != 0)
            revert RedeemOnCompoundFailed();
        if (_poolTokenAddress == cEth) IWETH(address(wEth)).deposit{value: _amount}(); // Turn the ETH received in wETH.
    }

    /// @dev Borrows underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(address _poolTokenAddress, uint256 _amount) internal {
        if ((ICToken(_poolTokenAddress).borrow(_amount) != 0)) revert BorrowOnCompoundFailed();
        if (_poolTokenAddress == cEth) IWETH(address(wEth)).deposit{value: _amount}(); // Turn the ETH received in wETH.
    }

    /// @dev Repays underlying tokens to Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function _repayToPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount
    ) internal {
        // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
        _amount = Math.min(
            _amount,
            ICToken(_poolTokenAddress).borrowBalanceCurrent(address(this)) // The debt of the contract.
        );

        if (_amount > 0) {
            if (_poolTokenAddress == cEth) {
                IWETH(wEth).withdraw(_amount); // Turn wETH into ETH.
                ICEther(_poolTokenAddress).repayBorrow{value: _amount}();
            } else {
                _underlyingToken.safeApprove(_poolTokenAddress, _amount);
                if (ICToken(_poolTokenAddress).repayBorrow(_amount) != 0)
                    revert RepayOnCompoundFailed();
            }
        }
    }

    /// @dev Enters the user into the market if not already there.
    /// @param _user The address of the user to update.
    /// @param _poolTokenAddress The address of the market to check.
    function _enterMarketIfNeeded(address _poolTokenAddress, address _user) internal {
        if (!userMembership[_poolTokenAddress][_user]) {
            userMembership[_poolTokenAddress][_user] = true;
            enteredMarkets[_user].push(_poolTokenAddress);
        }
    }

    /// @dev Removes the user from the market if its balances are null.
    /// @param _user The address of the user to update.
    /// @param _poolTokenAddress The address of the market to check.
    function _leaveMarketIfNeeded(address _poolTokenAddress, address _user) internal {
        if (
            userMembership[_poolTokenAddress][_user] &&
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P == 0 &&
            supplyBalanceInOf[_poolTokenAddress][_user].onPool == 0 &&
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P == 0 &&
            borrowBalanceInOf[_poolTokenAddress][_user].onPool == 0
        ) {
            uint256 index;
            while (enteredMarkets[_user][index] != _poolTokenAddress) {
                unchecked {
                    ++index;
                }
            }
            userMembership[_poolTokenAddress][_user] = false;

            uint256 length = enteredMarkets[_user].length;
            if (index != length - 1)
                enteredMarkets[_user][index] = enteredMarkets[_user][length - 1];
            enteredMarkets[_user].pop();
        }
    }
}
