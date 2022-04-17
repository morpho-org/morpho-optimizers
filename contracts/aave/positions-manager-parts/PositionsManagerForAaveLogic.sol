// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "../libraries/MatchingEngineFns.sol";

import "./PositionsManagerForAaveGettersSetters.sol";

/// @title PositionsManagerForAaveLogic.
/// @notice Main Logic of Morpho Protocol, implementation of the 5 main functionalities: supply, borrow, withdraw, repay, liquidate.
contract PositionsManagerForAaveLogic is PositionsManagerForAaveGettersSetters {
    using MatchingEngineFns for IMatchingEngineForAave;
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /// STRUCTS ///

    struct WithdrawVars {
        uint256 remainingToWithdraw;
        uint256 supplyPoolIndex;
        uint256 withdrawable;
        uint256 toWithdraw;
    }

    struct RepayVars {
        uint256 remainingToRepay;
        uint256 borrowPoolIndex;
        uint256 supplyPoolIndex;
        uint256 toRepay;
    }

    /// UPGRADE ///

    /// @notice Initializes the PositionsManagerForAave contract.
    /// @param _marketsManager The `marketsManager`.
    /// @param _matchingEngine The `matchingEngine`.
    /// @param _lendingPoolAddressesProvider The `addressesProvider`.
    function initialize(
        IMarketsManagerForAave _marketsManager,
        IMatchingEngineForAave _matchingEngine,
        ILendingPoolAddressesProvider _lendingPoolAddressesProvider,
        MaxGas memory _maxGas,
        uint8 _NDS
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        maxGas = _maxGas;
        marketsManager = _marketsManager;
        matchingEngine = _matchingEngine;
        addressesProvider = _lendingPoolAddressesProvider;
        lendingPool = ILendingPool(addressesProvider.getLendingPool());

        NDS = _NDS;
    }

    /// LOGIC ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);

        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 borrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        uint256 remainingToSupply = _amount;
        uint256 toRepay;

        /// Supply in P2P ///

        if (!marketsManager.noP2P(_poolTokenAddress)) {
            // Match borrow P2P delta first if any.
            if (delta.borrowP2PDelta > 0) {
                uint256 matchedDelta = Math.min(
                    delta.borrowP2PDelta.mulWadByRay(borrowPoolIndex),
                    remainingToSupply
                );
                if (matchedDelta > 0) {
                    toRepay += matchedDelta;
                    remainingToSupply -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.divWadByRay(borrowPoolIndex);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                remainingToSupply > 0 && borrowersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                uint256 matched = matchingEngine.matchBorrowersDC(
                    IAToken(_poolTokenAddress),
                    underlyingToken,
                    remainingToSupply,
                    _maxGasToConsume
                ); // In underlying.

                if (matched > 0) {
                    toRepay += matched;
                    remainingToSupply -= matched;
                    delta.borrowP2PAmount += matched.divWadByRay(
                        marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
                    );
                }
            }
        }

        if (toRepay > 0) {
            uint256 toAddInP2P = toRepay.divWadByRay(
                marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
            );

            delta.supplyP2PAmount += toAddInP2P;
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);

            toRepay = Math.min(
                toRepay,
                IVariableDebtToken(
                    lendingPool.getReserveData(address(underlyingToken)).variableDebtTokenAddress
                ).scaledBalanceOf(address(this))
                .mulWadByRay(borrowPoolIndex) // Current Morpho's debt on Aave.
            );

            if (toRepay > 0) _repayERC20ToPool(underlyingToken, toRepay); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Supply on pool ///

        if (remainingToSupply > 0) {
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupply
            .divWadByRay(lendingPool.getReserveNormalizedIncome(address(underlyingToken))); // In scaled balance.
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            _supplyToPool(underlyingToken, remainingToSupply); // Reverts on error.
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
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolSupplyIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        uint256 withdrawable = IAToken(_poolTokenAddress).balanceOf(address(this)); // The balance on pool.

        /// Borrow in P2P ///

        if (!marketsManager.noP2P(_poolTokenAddress)) {
            // Match supply P2P delta first if any.
            uint256 matchedDelta;
            if (delta.supplyP2PDelta > 0) {
                matchedDelta = Math.min(
                    delta.supplyP2PDelta.mulWadByRay(poolSupplyIndex),
                    remainingToBorrow,
                    withdrawable
                );
                if (matchedDelta > 0) {
                    toWithdraw += matchedDelta;
                    remainingToBorrow -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.divWadByRay(poolSupplyIndex);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                remainingToBorrow > 0 && suppliersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                uint256 matched = matchingEngine.matchSuppliersDC(
                    IAToken(_poolTokenAddress),
                    underlyingToken,
                    Math.min(remainingToBorrow, withdrawable - toWithdraw),
                    _maxGasToConsume
                ); // In underlying.

                if (matched > 0) {
                    toWithdraw += matched;
                    remainingToBorrow -= matched;
                    deltas[_poolTokenAddress].supplyP2PAmount += matched.divWadByRay(
                        marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
                    );
                }
            }
        }

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.divWadByRay(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            ); // In p2pUnit.

            deltas[_poolTokenAddress].borrowP2PAmount += toAddInP2P;
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);

            _withdrawFromPool(underlyingToken, toWithdraw); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Borrow on pool ///

        if (remainingToBorrow > 0) {
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrow
            .divWadByRay(lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))); // In adUnit.
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            _borrowFromPool(underlyingToken, remainingToBorrow);
        }

        underlyingToken.safeTransfer(msg.sender, _amount);
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
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.withdrawable = poolToken.balanceOf(address(this));
        vars.supplyPoolIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            vars.toWithdraw = Math.min(
                onPoolSupply.mulWadByRay(vars.supplyPoolIndex),
                vars.remainingToWithdraw,
                vars.withdrawable
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                onPoolSupply,
                vars.toWithdraw.divWadByRay(vars.supplyPoolIndex)
            ); // In poolToken.
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            if (vars.remainingToWithdraw == 0) {
                if (vars.toWithdraw > 0) _withdrawFromPool(underlyingToken, vars.toWithdraw); // Reverts on error.
                underlyingToken.safeTransfer(_receiver, _amount);
                _leaveMarkerIfNeeded(_poolTokenAddress, _supplier);
                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

        /// Transfer withdraw ///

        if (vars.remainingToWithdraw > 0 && !marketsManager.noP2P(_poolTokenAddress)) {
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                vars.remainingToWithdraw.divWadByRay(supplyP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            // Match Delta if any.
            if (delta.supplyP2PDelta > 0) {
                uint256 matchedDelta;
                matchedDelta = Math.min(
                    delta.supplyP2PDelta.mulWadByRay(vars.supplyPoolIndex),
                    vars.remainingToWithdraw,
                    vars.withdrawable - vars.toWithdraw
                );

                if (matchedDelta > 0) {
                    vars.toWithdraw += matchedDelta;
                    vars.remainingToWithdraw -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.divWadByRay(vars.supplyPoolIndex);
                    delta.supplyP2PAmount -= matchedDelta.divWadByRay(supplyP2PExchangeRate);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                vars.remainingToWithdraw > 0 &&
                suppliersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                // Match suppliers.
                uint256 matched = matchingEngine.matchSuppliersDC(
                    poolToken,
                    underlyingToken,
                    Math.min(vars.remainingToWithdraw, vars.withdrawable - vars.toWithdraw),
                    _maxGasToConsume / 2
                );

                if (matched > 0) {
                    vars.remainingToWithdraw -= matched;
                    vars.toWithdraw += matched;
                }
            }
        }

        if (vars.toWithdraw > 0) _withdrawFromPool(underlyingToken, vars.toWithdraw); // Reverts on error.

        /// Hard withdraw ///

        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = matchingEngine.unmatchBorrowersDC(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                _maxGasToConsume / 2
            );

            // If unmatched does not cover remainingToWithdraw, the difference is added to the borrow P2P delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.borrowP2PDelta += (vars.remainingToWithdraw - unmatched).divWadByRay(
                    lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))
                );
                emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PAmount);
            }

            delta.supplyP2PAmount -= vars.remainingToWithdraw.divWadByRay(supplyP2PExchangeRate);
            delta.borrowP2PAmount -= unmatched.divWadByRay(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            );
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            _borrowFromPool(underlyingToken, vars.remainingToWithdraw); // Reverts on error.
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
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.borrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            vars.toRepay = Math.min(
                borrowedOnPool.mulWadByRay(vars.borrowPoolIndex),
                vars.remainingToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                vars.toRepay.divWadByRay(vars.borrowPoolIndex)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            if (vars.remainingToRepay == 0) {
                vars.toRepay = Math.min(
                    vars.toRepay,
                    IVariableDebtToken(
                        lendingPool
                        .getReserveData(address(underlyingToken))
                        .variableDebtTokenAddress
                    ).scaledBalanceOf(address(this))
                    .mulWadByRay(vars.borrowPoolIndex) // The debt of the contract.
                );
                if (vars.toRepay > 0) _repayERC20ToPool(underlyingToken, vars.toRepay); // Reverts on error.
                _leaveMarkerIfNeeded(_poolTokenAddress, _user);
                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
        vars.supplyPoolIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= Math.min(
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P,
            vars.remainingToRepay.divWadByRay(borrowP2PExchangeRate)
        ); // In p2pUnit
        matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

        /// Fee repay ///

        uint256 feeToRepay = Math.min(
            (delta.borrowP2PAmount.mulWadByRay(borrowP2PExchangeRate) -
                delta.borrowP2PDelta.mulWadByRay(vars.borrowPoolIndex)) -
                (delta.supplyP2PAmount.mulWadByRay(supplyP2PExchangeRate) -
                    delta.supplyP2PDelta.mulWadByRay(vars.supplyPoolIndex)),
            vars.remainingToRepay
        );
        vars.remainingToRepay -= feeToRepay;

        /// Transfer repay ///

        if (vars.remainingToRepay > 0 && !marketsManager.noP2P(_poolTokenAddress)) {
            // Match Delta if any.
            if (delta.borrowP2PDelta > 0) {
                uint256 matchedDelta = Math.min(
                    delta.borrowP2PDelta.mulWadByRay(vars.borrowPoolIndex),
                    vars.remainingToRepay
                );

                if (matchedDelta > 0) {
                    vars.toRepay += matchedDelta;
                    vars.remainingToRepay -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.divWadByRay(vars.borrowPoolIndex);
                    delta.borrowP2PAmount -= matchedDelta.divWadByRay(borrowP2PExchangeRate);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }
            }

            if (
                vars.remainingToRepay > 0 &&
                borrowersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                // Match borrowers.
                uint256 matched = matchingEngine.matchBorrowersDC(
                    poolToken,
                    underlyingToken,
                    vars.remainingToRepay,
                    _maxGasToConsume / 2
                );

                if (matched > 0) {
                    vars.remainingToRepay -= matched;
                    vars.toRepay += matched;
                }
            }
        }

        // Manages the case where someone has repaid on behalf of Morpho.
        // The remaining tokens stay on the contract, and will be claimed as reserve by the governance.
        vars.toRepay = Math.min(
            vars.toRepay,
            IVariableDebtToken(
                lendingPool.getReserveData(address(underlyingToken)).variableDebtTokenAddress
            ).scaledBalanceOf(address(this))
            .mulWadByRay(vars.borrowPoolIndex) // The debt of the contract.
        );

        if (vars.toRepay > 0) _repayERC20ToPool(underlyingToken, vars.toRepay); // Reverts on error.

        /// Hard repay ///

        if (vars.remainingToRepay > 0) {
            uint256 unmatched = matchingEngine.unmatchSuppliersDC(
                _poolTokenAddress,
                vars.remainingToRepay,
                _maxGasToConsume / 2
            ); // Reverts on error.

            // If unmatched does not cover remainingToRepay, the difference is added to the supply P2P delta.
            if (unmatched < vars.remainingToRepay) {
                delta.supplyP2PDelta += (vars.remainingToRepay - unmatched).divWadByRay(
                    vars.supplyPoolIndex
                );
                emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
            }

            delta.supplyP2PAmount -= unmatched.divWadByRay(supplyP2PExchangeRate);
            delta.borrowP2PAmount -= vars.remainingToRepay.divWadByRay(borrowP2PExchangeRate);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            _supplyToPool(underlyingToken, vars.remainingToRepay); // Reverts on error.
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
    ) internal view {
        (uint256 debtValue, uint256 maxDebtValue, ) = _getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (debtValue > maxDebtValue) revert DebtValueAboveMax();
    }

    /// @dev Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeApprove(address(lendingPool), _amount);
        lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(ERC20 _underlyingToken, uint256 _amount) internal {
        lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(ERC20 _underlyingToken, uint256 _amount) internal {
        lendingPool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function _repayERC20ToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeApprove(address(lendingPool), _amount);
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
    }
}
