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
        uint256 remainingToSupplyToPool = _amount;

        /// Supply in P2P ///

        if (
            borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
            uint256 matched = matchingEngine.matchBorrowersDC(
                IAToken(_poolTokenAddress),
                underlyingToken,
                _amount,
                _maxGasToConsume
            ); // In underlying

            if (matched > 0) {
                _repayERC20ToPool(
                    underlyingToken,
                    matched,
                    lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))
                ); // Reverts on error

                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    supplyP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            }
            remainingToSupplyToPool -= matched;
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
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
            uint256 matched = matchingEngine.matchSuppliersDC(
                IAToken(_poolTokenAddress),
                underlyingToken,
                _amount,
                _maxGasToConsume
            ); // In underlying

            if (matched > 0) {
                matched = Math.min(matched, IAToken(_poolTokenAddress).balanceOf(address(this)));
                _withdrawERC20FromPool(underlyingToken, matched); // Reverts on error

                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.divWadByRay(
                    borrowP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            }

            remainingToBorrowOnPool -= matched;
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
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToWithdraw = _amount;

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            uint256 withdrawnInUnderlying = Math.min(
                Math.min(onPoolSupply.mulWadByRay(normalizedIncome), remainingToWithdraw),
                poolToken.balanceOf(address(this))
            );

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                onPoolSupply,
                withdrawnInUnderlying.divWadByRay(normalizedIncome)
            ); // In poolToken
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            if (withdrawnInUnderlying > 0)
                _withdrawERC20FromPool(underlyingToken, withdrawnInUnderlying); // Reverts on error
            remainingToWithdraw -= withdrawnInUnderlying;
        }

        /// Transfer withdraw ///

        if (remainingToWithdraw > 0) {
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                remainingToWithdraw.divWadByRay(
                    marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
                )
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            uint256 matched;
            if (
                suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                matched = matchingEngine.matchSuppliersDC(
                    poolToken,
                    underlyingToken,
                    remainingToWithdraw,
                    _maxGasToConsume / 2
                );

                if (matched > 0) {
                    matched = Math.min(
                        matched,
                        IAToken(_poolTokenAddress).balanceOf(address(this))
                    );
                    _withdrawERC20FromPool(underlyingToken, matched); // Reverts on error
                    remainingToWithdraw -= matched;
                }
            }

            /// Hard withdraw ///

            if (remainingToWithdraw > 0) {
                matchingEngine.unmatchBorrowersDC(
                    _poolTokenAddress,
                    remainingToWithdraw,
                    _maxGasToConsume / 2
                );

                _borrowERC20FromPool(underlyingToken, remainingToWithdraw); // Reverts on error
            }
        }

        underlyingToken.safeTransfer(_receiver, _amount);

        emit Withdrawn(
            _supplier,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][_receiver].onPool,
            supplyBalanceInOf[_poolTokenAddress][_receiver].inP2P
        );
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
        uint256 remainingToRepay = _amount;

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            uint256 repaidInUnderlying = Math.min(
                borrowedOnPool.mulWadByRay(normalizedVariableDebt),
                remainingToRepay
            );

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                repaidInUnderlying.divWadByRay(normalizedVariableDebt)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            if (repaidInUnderlying > 0)
                _repayERC20ToPool(underlyingToken, repaidInUnderlying, normalizedVariableDebt); // Reverts on error
            remainingToRepay -= repaidInUnderlying;
        }

        /// Transfer repay ///

        if (remainingToRepay > 0) {
            address poolTokenAddress = address(poolToken);
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(poolTokenAddress);
            uint256 matched;

            borrowBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
                borrowBalanceInOf[poolTokenAddress][_user].inP2P,
                remainingToRepay.divWadByRay(borrowP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(poolTokenAddress, _user);

            if (
                borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                matched = matchingEngine.matchBorrowersDC(
                    poolToken,
                    underlyingToken,
                    remainingToRepay,
                    _maxGasToConsume / 2
                );

                _repayERC20ToPool(
                    underlyingToken,
                    matched,
                    lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))
                ); // Reverts on error
                remainingToRepay -= matched;
            }

            /// Hard repay ///

            if (remainingToRepay > 0) {
                uint256 toSupply = matchingEngine.unmatchSuppliersDC(
                    poolTokenAddress,
                    remainingToRepay,
                    _maxGasToConsume / 2
                ); // Reverts on error

                if (toSupply > 0) _supplyERC20ToPool(underlyingToken, toSupply); // Reverts on error
            }
        }

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
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
