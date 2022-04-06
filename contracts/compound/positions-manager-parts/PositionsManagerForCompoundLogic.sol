// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "../libraries/MatchingEngineFns.sol";

import "./PositionsManagerForCompoundGettersSetters.sol";

/// @title PositionsManagerForCompoundLogic.
/// @notice Main Logic of Morpho Protocol, implementation of the 5 main functionalities: supply, borrow, withdraw, repay, liquidate.
contract PositionsManagerForCompoundLogic is PositionsManagerForCompoundGettersSetters {
    using MatchingEngineFns for IMatchingEngineForCompound;
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct WithdrawVars {
        uint256 remainingToWithdraw;
        uint256 supplyPoolIndex;
        uint256 maxToWithdraw;
        uint256 toWithdraw;
    }

    struct RepayVars {
        uint256 remainingToRepay;
        uint256 borrowPoolIndex;
        uint256 maxToRepay;
        uint256 toRepay;
    }

    /// UPGRADE ///

    /// @notice Initializes the PositionsManagerForCompound contract.
    /// @param _marketsManager The `marketsManager`.
    /// @param _matchingEngine The `matchingEngine`.
    /// @param _comptroller The `comptroller`.
    /// @param _maxGas The `maxGas`.
    /// @param _NDS The `NDS`.
    function initialize(
        IMarketsManagerForCompound _marketsManager,
        IMatchingEngineForCompound _matchingEngine,
        IComptroller _comptroller,
        MaxGas memory _maxGas,
        uint8 _NDS
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        marketsManager = _marketsManager;
        matchingEngine = _matchingEngine;
        comptroller = _comptroller;

        maxGas = _maxGas;
        NDS = _NDS;
    }

    /// LOGIC ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);

        ERC20 underlyingToken = ERC20(ICToken(_poolTokenAddress).underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        Delta storage delta = deltas[_poolTokenAddress];
        uint256 borrowPoolIndex = ICToken(_poolTokenAddress).borrowIndex();
        uint256 maxToRepay = ICToken(_poolTokenAddress).borrowBalanceCurrent(address(this)); // The maximum to repay is the current Morpho's debt on Compound.
        uint256 remainingToSupply = _amount;
        uint256 toRepay;

        /// Supply in P2P ///

        if (!marketsManager.noP2P(_poolTokenAddress)) {
            // Match borrow P2P delta first if any.
            uint256 matchedDelta;
            if (delta.borrowP2PDelta > 0) {
                matchedDelta = CompoundMath.min(
                    delta.borrowP2PDelta.mul(borrowPoolIndex),
                    remainingToSupply,
                    maxToRepay
                );
                if (matchedDelta > 0) {
                    toRepay += matchedDelta;
                    remainingToSupply -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.div(borrowPoolIndex);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                remainingToSupply > 0 && borrowersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                uint256 matched = CompoundMath.min(
                    matchingEngine.matchBorrowersDC(
                        ICToken(_poolTokenAddress),
                        remainingToSupply,
                        _maxGasToConsume
                    ),
                    maxToRepay - toRepay
                ); // In underlying.

                if (matched > 0) {
                    toRepay += matched;
                    remainingToSupply -= matched;
                    delta.borrowP2PAmount += matched.div(
                        marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
                    );
                }
            }
        }

        if (toRepay > 0) {
            uint256 toAddInP2P = toRepay.div(
                marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
            );

            delta.supplyP2PAmount += toAddInP2P;
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);

            _repayToPool(_poolTokenAddress, underlyingToken, toRepay); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Supply on pool ///

        if (remainingToSupply > 0) {
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupply.div(
                ICToken(_poolTokenAddress).exchangeRateCurrent()
            ); // In scaled balance.
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            _supplyToPool(_poolTokenAddress, underlyingToken, remainingToSupply); // Reverts on error.
        }
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);

        ERC20 underlyingToken = ERC20(ICToken(_poolTokenAddress).underlying());
        uint256 balanceBefore = underlyingToken.balanceOf(address(this));
        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolSupplyIndex = ICToken(_poolTokenAddress).exchangeRateCurrent();
        uint256 maxToWithdraw = ICToken(_poolTokenAddress).balanceOfUnderlying(address(this)); // The balance on pool.

        /// Borrow in P2P ///

        if (!marketsManager.noP2P(_poolTokenAddress)) {
            // Match supply P2P delta first if any.
            uint256 matchedDelta;
            if (delta.supplyP2PDelta > 0) {
                matchedDelta = CompoundMath.min(
                    delta.supplyP2PDelta.mul(poolSupplyIndex),
                    remainingToBorrow,
                    maxToWithdraw
                );
                if (matchedDelta > 0) {
                    toWithdraw += matchedDelta;
                    remainingToBorrow -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.div(poolSupplyIndex);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                remainingToBorrow > 0 && suppliersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                uint256 matched = CompoundMath.min(
                    matchingEngine.matchSuppliersDC(
                        ICToken(_poolTokenAddress),
                        remainingToBorrow,
                        _maxGasToConsume
                    ),
                    maxToWithdraw - toWithdraw
                ); // In underlying.

                if (matched > 0) {
                    toWithdraw += matched;
                    maxToWithdraw -= matched;
                    remainingToBorrow -= matched;
                    deltas[_poolTokenAddress].supplyP2PAmount += matched.div(
                        marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
                    );
                }
            }
        }

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.div(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            ); // In p2pUnit.

            deltas[_poolTokenAddress].borrowP2PAmount += toAddInP2P;
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);

            _withdrawFromPool(_poolTokenAddress, toWithdraw); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Borrow on pool ///

        if (_isAboveCompoundThreshold(_poolTokenAddress, remainingToBorrow)) {
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrow.div(
                ICToken(_poolTokenAddress).borrowIndex()
            ); // In cdUnit.
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            _borrowFromPool(_poolTokenAddress, remainingToBorrow);
        }

        // Due to rounding errors the balance may be lower than expected.
        uint256 balanceAfter = underlyingToken.balanceOf(address(this));

        underlyingToken.safeTransfer(msg.sender, balanceAfter - balanceBefore);
    }

    /// @dev Implements withdraw logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        ICToken poolToken = ICToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.underlying());
        WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.maxToWithdraw = poolToken.balanceOfUnderlying(address(this));
        vars.supplyPoolIndex = poolToken.exchangeRateCurrent();

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            vars.toWithdraw = CompoundMath.min(
                onPoolSupply.mul(vars.supplyPoolIndex),
                vars.remainingToWithdraw,
                vars.maxToWithdraw
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= CompoundMath.min(
                onPoolSupply,
                vars.toWithdraw.div(vars.supplyPoolIndex)
            ); // In poolToken.
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);
        }

        Delta storage delta = deltas[_poolTokenAddress];
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

        /// Transfer withdraw ///

        if (vars.remainingToWithdraw > 0 && !marketsManager.noP2P(_poolTokenAddress)) {
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= CompoundMath.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                vars.remainingToWithdraw.div(supplyP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            // Match Delta if any.
            if (delta.supplyP2PDelta > 0) {
                uint256 matchedDelta;
                matchedDelta = CompoundMath.min(
                    delta.supplyP2PDelta.mul(vars.supplyPoolIndex),
                    vars.remainingToWithdraw,
                    vars.maxToWithdraw - vars.toWithdraw
                );

                if (matchedDelta > 0) {
                    vars.toWithdraw += matchedDelta;
                    vars.remainingToWithdraw -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.div(vars.supplyPoolIndex);
                    delta.supplyP2PAmount -= matchedDelta.div(supplyP2PExchangeRate);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                vars.remainingToWithdraw > 0 &&
                suppliersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                // Match suppliers.
                uint256 matched = CompoundMath.min(
                    matchingEngine.matchSuppliersDC(
                        poolToken,
                        vars.remainingToWithdraw,
                        _maxGasToConsume / 2
                    ),
                    vars.maxToWithdraw - vars.toWithdraw
                );

                if (matched > 0) {
                    vars.remainingToWithdraw -= matched;
                    vars.toWithdraw += matched;
                }
            }
        }

        if (vars.toWithdraw > 0) _withdrawFromPool(_poolTokenAddress, vars.toWithdraw); // Reverts on error.

        /// Hard withdraw ///

        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = matchingEngine.unmatchBorrowersDC(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                _maxGasToConsume / 2
            );

            // If unmatched does not cover remainingToWithdraw, the difference is added to the borrow P2P delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.borrowP2PDelta += (vars.remainingToWithdraw - unmatched).div(
                    poolToken.borrowIndex()
                );
                emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PAmount);
            }

            delta.supplyP2PAmount -= vars.remainingToWithdraw.div(supplyP2PExchangeRate);
            delta.borrowP2PAmount -= unmatched.div(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            );
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            _borrowFromPool(_poolTokenAddress, vars.remainingToWithdraw); // Reverts on error.
        }

        underlyingToken.safeTransfer(_receiver, _amount);
        _leaveMarkerIfNeeded(_poolTokenAddress, _supplier);
    }

    /// @dev Implements repay logic.
    /// @dev Note: `msg.sender` must have approved this contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _repay(
        address _poolTokenAddress,
        address _user,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        ICToken poolToken = ICToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.borrowPoolIndex = poolToken.borrowIndex();
        vars.maxToRepay = poolToken.borrowBalanceCurrent(address(this)); // The debt of the contract.

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            vars.toRepay = CompoundMath.min(
                borrowedOnPool.mul(vars.borrowPoolIndex),
                vars.remainingToRepay,
                vars.maxToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= CompoundMath.min(
                borrowedOnPool,
                vars.toRepay.div(vars.borrowPoolIndex)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);
        }

        Delta storage delta = deltas[_poolTokenAddress];
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);

        /// Transfer repay ///

        if (vars.remainingToRepay > 0 && !marketsManager.noP2P(_poolTokenAddress)) {
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= CompoundMath.min(
                borrowBalanceInOf[_poolTokenAddress][_user].inP2P,
                vars.remainingToRepay.div(borrowP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            // Match Delta if any.
            if (delta.borrowP2PDelta > 0) {
                uint256 matchedDelta = CompoundMath.min(
                    delta.borrowP2PDelta.mul(vars.borrowPoolIndex),
                    vars.remainingToRepay,
                    vars.maxToRepay - vars.toRepay
                );

                if (matchedDelta > 0) {
                    vars.toRepay += matchedDelta;
                    vars.remainingToRepay -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.div(vars.borrowPoolIndex);
                    delta.borrowP2PAmount -= matchedDelta.div(borrowP2PExchangeRate);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }
            }

            if (
                vars.remainingToRepay > 0 &&
                borrowersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                // Match borrowers.
                uint256 matched = CompoundMath.min(
                    matchingEngine.matchBorrowersDC(
                        poolToken,
                        vars.remainingToRepay,
                        _maxGasToConsume / 2
                    ),
                    vars.maxToRepay - vars.toRepay
                );

                if (matched > 0) {
                    vars.remainingToRepay -= matched;
                    vars.toRepay += matched;
                }
            }
        }

        if (vars.toRepay > 0) _repayToPool(_poolTokenAddress, underlyingToken, vars.toRepay); // Reverts on error.

        /// Hard repay ///

        if (vars.remainingToRepay > 0) {
            uint256 unmatched = matchingEngine.unmatchSuppliersDC(
                _poolTokenAddress,
                vars.remainingToRepay,
                _maxGasToConsume / 2
            ); // Reverts on error.

            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

            // If P2P supply supplyAmount < remainingToRepay, the rest stays on the contract (reserve factor).
            uint256 toSupply = CompoundMath.min(
                vars.remainingToRepay,
                delta.supplyP2PAmount.mul(supplyP2PExchangeRate)
            );

            // If unmatched does not cover remainingToRepay, the difference is added to the supply P2P delta.
            if (unmatched < vars.remainingToRepay) {
                delta.supplyP2PDelta += (vars.remainingToRepay - unmatched).div(
                    poolToken.exchangeRateCurrent()
                );
                emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
            }

            delta.supplyP2PAmount -= unmatched.div(supplyP2PExchangeRate);
            delta.borrowP2PAmount -= vars.remainingToRepay.div(borrowP2PExchangeRate);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            if (toSupply > 0) _supplyToPool(_poolTokenAddress, underlyingToken, toSupply); // Reverts on error.
        }
        _leaveMarkerIfNeeded(_poolTokenAddress, _user);
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

    /// @dev Removes the user from the market if he has no funds or borrow on it.
    /// @param _user The address of the user to update.
    /// @param _poolTokenAddress The address of the market to check.
    function _leaveMarkerIfNeeded(address _poolTokenAddress, address _user) internal {
        if (
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

    /// @dev Checks whether the user can borrow/withdraw or not.
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
        (uint256 debtValue, uint256 maxDebtValue) = _getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (debtValue > maxDebtValue) revert DebtValueAboveMax();
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
        _underlyingToken.safeApprove(_poolTokenAddress, _amount);
        if (ICToken(_poolTokenAddress).mint(_amount) != 0) revert MintOnCompoundFailed();
    }

    /// @dev Withdraws underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(address _poolTokenAddress, uint256 _amount) internal {
        if (ICToken(_poolTokenAddress).redeemUnderlying(_amount) != 0)
            revert RedeemOnCompoundFailed();
    }

    /// @dev Borrows underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(address _poolTokenAddress, uint256 _amount) internal {
        if ((ICToken(_poolTokenAddress).borrow(_amount) != 0)) revert BorrowOnCompoundFailed();
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
        _underlyingToken.safeApprove(_poolTokenAddress, _amount);
        if (ICToken(_poolTokenAddress).repayBorrow(_amount) != 0) revert RepayOnCompoundFailed();
    }

    /// @dev Returns whether it is unsafe supply/witdhraw due to coumpound's revert on low levels of precision or not.
    /// @param _amount The amount of token considered for depositing/redeeming.
    /// @param _poolTokenAddress poolToken address of the considered market.
    /// @return Whether to continue or not.
    function _isAboveCompoundThreshold(address _poolTokenAddress, uint256 _amount)
        internal
        view
        returns (bool)
    {
        ERC20 underlyingToken = ERC20(ICToken(_poolTokenAddress).underlying());
        uint8 tokenDecimals = underlyingToken.decimals();
        if (tokenDecimals > CTOKEN_DECIMALS) {
            // Multiply by 2 to have a safety buffer.
            unchecked {
                return (_amount > 2 * 10**(tokenDecimals - CTOKEN_DECIMALS));
            }
        } else return true;
    }
}