// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "../libraries/MatchingEngineFns.sol";

import "./PositionsManagerForAaveGettersSetters.sol";

/// @title PositionsManagerForAaveLogic.
/// @notice Main Logic of Morpho Protocol, implementation of the 5 main functionalities: supply, borrow, withdraw, repay, liquidate.
contract PositionsManagerForAaveLogic is PositionsManagerForAaveGettersSetters {
    using MatchingEngineFns for IMatchingEngineForAave;
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;

    /// UPGRADE ///

    /// @notice Initializes the PositionsManagerForAave contract.
    /// @param _marketsManager The `marketsManager`.
    /// @param _matchingEngine The `matchingEngine`.
    /// @param _lendingPoolAddressesProvider The `addressesProvider`.
    /// @param _swapManager The `swapManager`.
    function initialize(
        IMarketsManagerForAave _marketsManager,
        IMatchingEngineForAave _matchingEngine,
        ILendingPoolAddressesProvider _lendingPoolAddressesProvider,
        ISwapManager _swapManager,
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
        swapManager = _swapManager;

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
        _handleMembership(_poolTokenAddress, msg.sender);

        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        Delta storage delta = deltas[_poolTokenAddress];
        uint256 borrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        uint256 maxToRepay = IVariableDebtToken(
            lendingPool.getReserveData(address(underlyingToken)).variableDebtTokenAddress
        ).scaledBalanceOf(address(this))
        .mulWadByRay(borrowPoolIndex); // The maximum to repay is the current Morpho's debt on Aave.
        uint256 remainingToSupply = _amount;
        uint256 toRepay;

        /// Match Delta if any ///

        uint256 matchedDelta;
        // Match borrow P2P delta first if any.
        if (delta.borrowP2PDelta > 0) {
            matchedDelta = Math.min(
                delta.borrowP2PDelta.mulWadByRay(borrowPoolIndex),
                Math.min(remainingToSupply, maxToRepay)
            );
        }

        if (matchedDelta > 0) {
            toRepay += matchedDelta;
            maxToRepay -= matchedDelta;
            remainingToSupply -= matchedDelta;
            delta.borrowP2PDelta -= matchedDelta.divWadByRay(borrowPoolIndex);
            emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
        }

        /// Supply in P2P ///

        if (
            remainingToSupply > 0 &&
            borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 matched = Math.min(
                matchingEngine.matchBorrowersDC(
                    IAToken(_poolTokenAddress),
                    underlyingToken,
                    remainingToSupply,
                    _maxGasToConsume
                ),
                maxToRepay
            ); // In underlying.

            if (matched > 0) {
                toRepay += matched;
                matchedDelta += matched;
                remainingToSupply -= matched;
                delta.borrowP2PAmount += matched.divWadByRay(
                    marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
                );
            }
        }

        if (toRepay > 0) {
            uint256 toAddInP2P = toRepay.divWadByRay(
                marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
            );

            delta.supplyP2PAmount += toAddInP2P;
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);

            _repayERC20ToPool(underlyingToken, toRepay); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Supply on pool ///

        if (remainingToSupply > 0) {
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupply
            .divWadByRay(lendingPool.getReserveNormalizedIncome(address(underlyingToken))); // In scaled balance.
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            _supplyERC20ToPool(underlyingToken, remainingToSupply); // Reverts on error.
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
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolSupplyIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        uint256 maxToWithdraw = IAToken(_poolTokenAddress).balanceOf(address(this)); // The balance on pool.

        /// Match Delta if any ///

        uint256 matchedDelta;
        // Match supply P2P delta first if any.
        if (delta.supplyP2PDelta > 0)
            matchedDelta = Math.min(
                delta.supplyP2PDelta.mulWadByRay(poolSupplyIndex),
                Math.min(remainingToBorrow, maxToWithdraw)
            );

        if (matchedDelta > 0) {
            toWithdraw += matchedDelta;
            maxToWithdraw -= matchedDelta;
            remainingToBorrow -= matchedDelta;
            delta.supplyP2PDelta -= matchedDelta.divWadByRay(poolSupplyIndex);
            emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
        }

        /// Borrow in P2P ///

        if (
            remainingToBorrow > 0 &&
            suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 matched = Math.min(
                matchingEngine.matchSuppliersDC(
                    IAToken(_poolTokenAddress),
                    underlyingToken,
                    remainingToBorrow,
                    _maxGasToConsume
                ),
                maxToWithdraw
            ); // In underlying.

            if (matched > 0) {
                toWithdraw += matched;
                maxToWithdraw -= matched;
                remainingToBorrow -= matched;
                deltas[_poolTokenAddress].supplyP2PAmount += matched.divWadByRay(
                    marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
                );
            }
        }

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.divWadByRay(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            ); // In p2pUnit.

            deltas[_poolTokenAddress].borrowP2PAmount += toAddInP2P;
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);

            _withdrawERC20FromPool(underlyingToken, toWithdraw); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Borrow on pool ///

        if (remainingToBorrow > 0) {
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrow
            .divWadByRay(lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))); // In adUnit.
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            _borrowERC20FromPool(underlyingToken, remainingToBorrow);
        }

        underlyingToken.safeTransfer(msg.sender, _amount);
    }

    struct WithdrawVars {
        uint256 remainingToWithdraw;
        uint256 supplyPoolIndex;
        uint256 maxToWithdraw;
        uint256 toWithdraw;
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
        if (_amount == 0) revert AmountIsZero();
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.maxToWithdraw = poolToken.balanceOf(address(this));
        vars.supplyPoolIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            vars.toWithdraw = Math.min(
                onPoolSupply.mulWadByRay(vars.supplyPoolIndex),
                Math.min(vars.remainingToWithdraw, vars.maxToWithdraw)
            );
            vars.maxToWithdraw -= vars.toWithdraw;
            vars.remainingToWithdraw -= vars.toWithdraw;

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                onPoolSupply,
                vars.toWithdraw.divWadByRay(vars.supplyPoolIndex)
            ); // In poolToken.
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);
        }

        Delta storage delta = deltas[_poolTokenAddress];
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

        if (vars.remainingToWithdraw > 0) {
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                vars.remainingToWithdraw.divWadByRay(supplyP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            /// Match Delta if any ///

            if (delta.supplyP2PDelta > 0) {
                uint256 matchedDelta;
                matchedDelta = Math.min(
                    delta.supplyP2PDelta.mulWadByRay(vars.supplyPoolIndex),
                    Math.min(vars.remainingToWithdraw, vars.maxToWithdraw)
                );

                if (matchedDelta > 0) {
                    vars.toWithdraw += matchedDelta;
                    vars.maxToWithdraw -= matchedDelta;
                    vars.remainingToWithdraw -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.divWadByRay(vars.supplyPoolIndex);
                    delta.supplyP2PAmount -= matchedDelta.divWadByRay(supplyP2PExchangeRate);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }
            }

            /// Transfer withdraw ///

            if (
                vars.remainingToWithdraw > 0 &&
                suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                // Match suppliers.
                uint256 matched = Math.min(
                    matchingEngine.matchSuppliersDC(
                        poolToken,
                        underlyingToken,
                        vars.remainingToWithdraw,
                        _maxGasToConsume / 2
                    ),
                    vars.maxToWithdraw
                );

                if (matched > 0) {
                    vars.remainingToWithdraw -= matched;
                    vars.toWithdraw += matched;
                }
            }
        }

        if (vars.toWithdraw > 0) _withdrawERC20FromPool(underlyingToken, vars.toWithdraw); // Reverts on error.

        /// Hard withdraw ///

        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = matchingEngine.unmatchBorrowersDC(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                _maxGasToConsume / 2
            );

            // If new borrow P2P delta.
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

            _borrowERC20FromPool(underlyingToken, vars.remainingToWithdraw); // Reverts on error.
        }

        underlyingToken.safeTransfer(_receiver, _amount);
    }

    struct RepayVars {
        uint256 remainingToRepay;
        uint256 borrowPoolIndex;
        uint256 maxToRepay;
        uint256 toRepay;
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
        if (_amount == 0) revert AmountIsZero();
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.borrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        vars.maxToRepay = IVariableDebtToken(
            lendingPool.getReserveData(address(underlyingToken)).variableDebtTokenAddress
        ).scaledBalanceOf(address(this))
        .mulWadByRay(vars.borrowPoolIndex); // The debt of the contract.

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            vars.toRepay = Math.min(
                borrowedOnPool.mulWadByRay(vars.borrowPoolIndex),
                Math.min(vars.remainingToRepay, vars.maxToRepay)
            );
            vars.maxToRepay -= vars.toRepay;
            vars.remainingToRepay -= vars.toRepay;

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                vars.toRepay.divWadByRay(vars.borrowPoolIndex)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);
        }

        /// Transfer repay ///

        Delta storage delta = deltas[_poolTokenAddress];
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);

        if (vars.remainingToRepay > 0) {
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= Math.min(
                borrowBalanceInOf[_poolTokenAddress][_user].inP2P,
                vars.remainingToRepay.divWadByRay(borrowP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            /// Match Delta if any ///

            if (delta.borrowP2PDelta > 0) {
                uint256 matchedDelta = Math.min(
                    delta.borrowP2PDelta.mulWadByRay(vars.borrowPoolIndex),
                    Math.min(vars.remainingToRepay, vars.maxToRepay)
                );

                if (matchedDelta > 0) {
                    vars.toRepay += matchedDelta;
                    vars.maxToRepay -= matchedDelta;
                    vars.remainingToRepay -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.divWadByRay(vars.borrowPoolIndex);
                    delta.borrowP2PAmount -= matchedDelta.divWadByRay(borrowP2PExchangeRate);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }
            }

            if (
                vars.remainingToRepay > 0 &&
                borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                // Match borrowers.
                uint256 matched = Math.min(
                    matchingEngine.matchBorrowersDC(
                        poolToken,
                        underlyingToken,
                        vars.remainingToRepay,
                        _maxGasToConsume / 2
                    ),
                    vars.maxToRepay
                );

                if (matched > 0) {
                    vars.remainingToRepay -= matched;
                    vars.toRepay += matched;
                }
            }
        }

        if (vars.toRepay > 0) _repayERC20ToPool(underlyingToken, vars.toRepay); // Reverts on error.

        /// Hard repay ///

        if (vars.remainingToRepay > 0) {
            uint256 unmatched = matchingEngine.unmatchSuppliersDC(
                _poolTokenAddress,
                vars.remainingToRepay,
                _maxGasToConsume / 2
            ); // Reverts on error.

            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

            // If P2P supply supplyAmount < remainingToRepay, the rest stays on the contract (reserve factor).
            uint256 toSupply = Math.min(
                vars.remainingToRepay,
                delta.supplyP2PAmount.mulWadByRay(supplyP2PExchangeRate)
            );

            // If unmatched does not cover vars.remainingToRepay, supply P2P delta is created.
            if (unmatched < vars.remainingToRepay) {
                delta.supplyP2PDelta += (vars.remainingToRepay - unmatched).divWadByRay(
                    lendingPool.getReserveNormalizedIncome(address(underlyingToken))
                );
                emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
            }

            delta.supplyP2PAmount -= unmatched.divWadByRay(supplyP2PExchangeRate);
            delta.borrowP2PAmount -= vars.remainingToRepay.divWadByRay(borrowP2PExchangeRate);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            if (toSupply > 0) _supplyERC20ToPool(underlyingToken, toSupply); // Reverts on error.
        }
    }

    ///@dev Enters the user into the market if not already there.
    ///@param _user The address of the user to update.
    ///@param _poolTokenAddress The address of the market to check.
    function _handleMembership(address _poolTokenAddress, address _user) internal {
        if (!userMembership[_poolTokenAddress][_user]) {
            userMembership[_poolTokenAddress][_user] = true;
            enteredMarkets[_user].push(_poolTokenAddress);
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

    /// @dev Returns the debt value, max debt value of a given user.
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
        view
        returns (
            uint256 debtValue,
            uint256 maxDebtValue,
            uint256 liquidationValue
        )
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
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
                liquidationValue += assetData.liquidationValue;
                maxDebtValue += assetData.maxDebtValue;
                debtValue += assetData.debtValue;
                ++i;
            }

            if (_poolTokenAddress == poolTokenEntered) {
                debtValue += (_borrowedAmount * assetData.underlyingPrice) / assetData.tokenUnit;

                uint256 maxDebtValueSub = (_withdrawnAmount *
                    assetData.underlyingPrice *
                    assetData.ltv) / (assetData.tokenUnit * MAX_BASIS_POINTS);
                uint256 liquidationValueSub = (_withdrawnAmount *
                    assetData.underlyingPrice *
                    assetData.liquidationValue) / (assetData.tokenUnit * MAX_BASIS_POINTS);

                unchecked {
                    maxDebtValue -= maxDebtValue < maxDebtValueSub ? maxDebtValue : maxDebtValueSub;
                    liquidationValue -= liquidationValue < liquidationValueSub
                        ? liquidationValue
                        : liquidationValueSub;
                }
            }
        }
    }

    /// @dev Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyERC20ToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeApprove(address(lendingPool), _amount);
        lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    function _withdrawERC20FromPool(ERC20 _underlyingToken, uint256 _amount) internal {
        lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowERC20FromPool(ERC20 _underlyingToken, uint256 _amount) internal {
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
