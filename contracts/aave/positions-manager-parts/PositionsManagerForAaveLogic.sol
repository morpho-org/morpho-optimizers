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

    struct Vars {
        uint256 supplyP2pExchangeRate;
        uint256 borrowP2pExchangeRate;
        uint256 supplyPoolIndex;
        uint256 borrowPoolIndex;
    }

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
        Delta storage delta = deltas[_poolTokenAddress];
        _handleMembership(_poolTokenAddress, msg.sender);
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToSupplyToPool = _amount;

        /// Supply in P2P ///

        if (
            borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

            // Match borrow P2P delta first.
            uint256 matchedDelta;
            if (delta.borrowP2PDelta > 0) {
                uint256 borrowPoolIndex = lendingPool.getReserveNormalizedIncome(
                    address(underlyingToken)
                );
                matchedDelta = Math.min(
                    delta.borrowP2PDelta.mulWadByRay(borrowPoolIndex),
                    remainingToSupplyToPool
                );
                remainingToSupplyToPool -= matchedDelta;
                delta.borrowP2PDelta -= matchedDelta.divWadByRay(borrowPoolIndex);
                emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
            }

            uint256 matched;

            if (remainingToSupplyToPool > 0) {
                matched = matchingEngine.matchBorrowersDC(
                    IAToken(_poolTokenAddress),
                    underlyingToken,
                    remainingToSupplyToPool,
                    _maxGasToConsume
                ); // In underlying
                remainingToSupplyToPool -= matched;
            }

            delta.supplyP2PAmount += (matched + matchedDelta).divWadByRay(supplyP2PExchangeRate);
            delta.borrowP2PAmount += matched.divWadByRay(
                marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
            );

            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            if (matched + matchedDelta > 0) {
                _repayERC20ToPool(
                    underlyingToken,
                    matched + matchedDelta,
                    lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))
                ); // Reverts on error

                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    supplyP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            }
        }

        /// Supply on pool ///

        if (remainingToSupplyToPool > 0) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupplyToPool
            .divWadByRay(normalizedIncome); // Scaled Balance
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            _supplyERC20ToPool(underlyingToken, remainingToSupplyToPool); // Reverts on error
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
        uint256 remainingToBorrowOnPool = _amount;

        /// Borrow in P2P ///

        if (
            suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            Delta storage delta = deltas[_poolTokenAddress];
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);

            uint256 matchedDelta;
            // Match borrow P2P delta first.
            if (delta.supplyP2PDelta > 0) {
                uint256 supplyPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
                    address(underlyingToken)
                );
                matchedDelta = Math.min(
                    delta.supplyP2PDelta.mulWadByRay(supplyPoolIndex),
                    remainingToBorrowOnPool
                );
                remainingToBorrowOnPool -= matchedDelta;
                delta.supplyP2PDelta -= matchedDelta.divWadByRay(supplyPoolIndex);
                emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
            }

            uint256 matched;
            if (remainingToBorrowOnPool > 0) {
                matched = matchingEngine.matchSuppliersDC(
                    IAToken(_poolTokenAddress),
                    underlyingToken,
                    _amount,
                    _maxGasToConsume
                ); // In underlying
                remainingToBorrowOnPool -= matched;
            }

            deltas[_poolTokenAddress].supplyP2PAmount += matched.divWadByRay(
                marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
            );
            deltas[_poolTokenAddress].borrowP2PAmount += (matched + matchedDelta).divWadByRay(
                borrowP2PExchangeRate
            );

            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            if (matched + matchedDelta > 0) {
                matched = Math.min(matched, IAToken(_poolTokenAddress).balanceOf(address(this)));
                _withdrawERC20FromPool(underlyingToken, matched + matchedDelta); // Reverts on error

                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += (matched + matchedDelta)
                .divWadByRay(borrowP2PExchangeRate); // In p2pUnit
                matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            }
        }

        /// Borrow on pool ///

        if (remainingToBorrowOnPool > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrowOnPool
            .divWadByRay(normalizedVariableDebt); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            _borrowERC20FromPool(underlyingToken, remainingToBorrowOnPool);
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
        if (_amount == 0) revert AmountIsZero();
        Vars memory vars;
        Delta storage delta = deltas[_poolTokenAddress];
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToWithdraw = _amount;

        vars.borrowP2pExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
        vars.supplyP2pExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
        vars.borrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        vars.supplyPoolIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            uint256 withdrawnInUnderlying = Math.min(
                Math.min(onPoolSupply.mulWadByRay(vars.supplyPoolIndex), remainingToWithdraw),
                poolToken.balanceOf(address(this))
            );

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                onPoolSupply,
                withdrawnInUnderlying.divWadByRay(vars.supplyPoolIndex)
            ); // In poolToken
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            if (withdrawnInUnderlying > 0)
                _withdrawERC20FromPool(underlyingToken, withdrawnInUnderlying); // Reverts on error
            remainingToWithdraw -= withdrawnInUnderlying;
        }

        /// Transfer withdraw ///

        if (remainingToWithdraw > 0) {
            uint256 matched;
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                remainingToWithdraw.divWadByRay(vars.supplyP2pExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            if (
                suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                // Reduce supply P2P delta first

                uint256 matchedDelta;
                if (delta.supplyP2PDelta > 0) {
                    matchedDelta = Math.min(
                        delta.supplyP2PDelta.mulWadByRay(vars.supplyPoolIndex),
                        remainingToWithdraw
                    );
                    remainingToWithdraw -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.divWadByRay(vars.supplyPoolIndex);
                    delta.supplyP2PAmount -= matchedDelta.divWadByRay(vars.supplyP2pExchangeRate);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }

                // match suppliers

                if (remainingToWithdraw > 0) {
                    matched = matchingEngine.matchSuppliersDC(
                        poolToken,
                        underlyingToken,
                        remainingToWithdraw,
                        _maxGasToConsume / 2
                    );
                    remainingToWithdraw -= matched;
                }

                matched = Math.min(matched, IAToken(_poolTokenAddress).balanceOf(address(this)));
                if (matched > 0) {
                    _withdrawERC20FromPool(underlyingToken, matched); // Reverts on error
                }
            }

            /// Hard withdraw ///

            if (remainingToWithdraw > 0) {
                matched = matchingEngine.unmatchBorrowersDC(
                    _poolTokenAddress,
                    remainingToWithdraw,
                    _maxGasToConsume / 2
                );

                if (matched < remainingToWithdraw) {
                    delta.borrowP2PDelta += (remainingToWithdraw - matched).divWadByRay(
                        vars.borrowPoolIndex
                    );
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PAmount);
                }

                delta.supplyP2PAmount -= remainingToWithdraw.divWadByRay(
                    vars.supplyP2pExchangeRate
                );
                delta.borrowP2PAmount -= matched.divWadByRay(vars.borrowP2pExchangeRate);

                _borrowERC20FromPool(underlyingToken, remainingToWithdraw); // Reverts on error
                emit P2PAmountsUpdated(
                    _poolTokenAddress,
                    delta.supplyP2PAmount,
                    delta.borrowP2PAmount
                );
            }
        }

        underlyingToken.safeTransfer(_receiver, _amount);
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
        Vars memory vars;
        Delta storage delta = deltas[_poolTokenAddress];
        if (_amount == 0) revert AmountIsZero();
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        vars.borrowP2pExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
        vars.supplyP2pExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
        vars.borrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        vars.supplyPoolIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            uint256 repaidInUnderlying = Math.min(
                borrowedOnPool.mulWadByRay(vars.borrowPoolIndex),
                remainingToRepay
            );

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                repaidInUnderlying.divWadByRay(vars.borrowPoolIndex)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            if (repaidInUnderlying > 0)
                _repayERC20ToPool(underlyingToken, repaidInUnderlying, vars.borrowPoolIndex); // Reverts on error
            remainingToRepay -= repaidInUnderlying;
        }

        /// Transfer repay ///

        if (remainingToRepay > 0) {
            uint256 matched;

            borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= Math.min(
                borrowBalanceInOf[_poolTokenAddress][_user].inP2P,
                remainingToRepay.divWadByRay(vars.borrowP2pExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            if (
                borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                uint256 matchedDelta;

                // Reduce supply P2P delta first
                if (delta.borrowP2PDelta > 0) {
                    matchedDelta = Math.min(
                        delta.borrowP2PDelta.mulWadByRay(vars.borrowPoolIndex),
                        remainingToRepay
                    );
                    remainingToRepay -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.divWadByRay(vars.borrowPoolIndex);
                    delta.borrowP2PAmount -= matchedDelta.divWadByRay(vars.borrowP2pExchangeRate);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }

                if (remainingToRepay > 0) {
                    matched = matchingEngine.matchBorrowersDC(
                        poolToken,
                        underlyingToken,
                        remainingToRepay,
                        _maxGasToConsume / 2
                    );
                    remainingToRepay -= matched;
                }

                if (matched + matchedDelta > 0)
                    _repayERC20ToPool(
                        underlyingToken,
                        matched + matchedDelta,
                        vars.borrowPoolIndex
                    ); // Reverts on error
            }

            /// Hard repay ///

            if (remainingToRepay > 0) {
                matched = matchingEngine.unmatchSuppliersDC(
                    _poolTokenAddress,
                    remainingToRepay,
                    _maxGasToConsume / 2
                ); // Reverts on error

                // if new supply P2P delta
                if (matched < remainingToRepay) {
                    delta.supplyP2PDelta += (remainingToRepay - matched).divWadByRay(
                        vars.borrowPoolIndex
                    );
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }

                delta.supplyP2PAmount -= matched.divWadByRay(vars.supplyP2pExchangeRate);
                delta.borrowP2PAmount -= remainingToRepay.divWadByRay(vars.borrowP2pExchangeRate);

                // If P2P supply supplyAmount < remainingToRepay, the rest stays on the contract (reserve factor)
                remainingToRepay = Math.min(
                    remainingToRepay,
                    delta.supplyP2PAmount.mulWadByRay(vars.supplyP2pExchangeRate)
                );

                if (remainingToRepay > 0) _supplyERC20ToPool(underlyingToken, remainingToRepay); // Reverts on error
                emit P2PAmountsUpdated(
                    _poolTokenAddress,
                    delta.supplyP2PAmount,
                    delta.borrowP2PAmount
                );
            }
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
    /// @param _normalizedVariableDebt The normalized variable debt on Aave.
    function _repayERC20ToPool(
        ERC20 _underlyingToken,
        uint256 _amount,
        uint256 _normalizedVariableDebt
    ) internal {
        _underlyingToken.safeApprove(address(lendingPool), _amount);
        IVariableDebtToken variableDebtToken = IVariableDebtToken(
            lendingPool.getReserveData(address(_underlyingToken)).variableDebtTokenAddress
        );
        // Do not repay more than the contract's debt on Aave
        _amount = Math.min(
            _amount,
            variableDebtToken.scaledBalanceOf(address(this)).mulWadByRay(_normalizedVariableDebt)
        );
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
    }
}
