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
        _handleMembership(_poolTokenAddress, msg.sender);
        marketsManager.updateRates(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(ICToken(_poolTokenAddress).underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToSupplyToPool = _amount;

        /// Supply in P2P ///

        if (
            borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
            uint256 matched = matchingEngine.matchBorrowersDC(
                ICToken(_poolTokenAddress),
                _amount,
                _maxGasToConsume
            ); // In underlying

            if ((_isAboveCompoundThreshold(_poolTokenAddress, matched))) {
                _repayToPool(_poolTokenAddress, underlyingToken, matched); // Reverts on error

                supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.div(
                    supplyP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
                remainingToSupplyToPool -= matched;
            }
        }

        /// Supply on pool ///

        if (_isAboveCompoundThreshold(_poolTokenAddress, remainingToSupplyToPool)) {
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupplyToPool.div(
                ICToken(_poolTokenAddress).exchangeRateCurrent()
            ); // Scaled Balance
            matchingEngine.updateSuppliersDC(_poolTokenAddress, msg.sender);
            _supplyToPool(_poolTokenAddress, underlyingToken, remainingToSupplyToPool); // Reverts on error
        }
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        uint256 remainingToBorrowOnPool = _amount;

        /// Borrow in P2P ///

        if (
            suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
            !marketsManager.noP2P(_poolTokenAddress)
        ) {
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
            uint256 matched = matchingEngine.matchSuppliersDC(
                ICToken(_poolTokenAddress),
                _amount,
                _maxGasToConsume
            ); // In underlying

            if (_isAboveCompoundThreshold(_poolTokenAddress, matched)) {
                matched = Math.min(matched, ICToken(_poolTokenAddress).balanceOf(address(this)));
                _withdrawFromPool(_poolTokenAddress, matched); // Reverts on error

                borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += matched.div(
                    borrowP2PExchangeRate
                ); // In p2pUnit
                matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
                remainingToBorrowOnPool -= matched;
            }
        }

        /// Borrow on pool ///

        if (_isAboveCompoundThreshold(_poolTokenAddress, remainingToBorrowOnPool)) {
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrowOnPool.div(
                ICToken(_poolTokenAddress).borrowIndex()
            ); // In cdUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, msg.sender);
            _borrowFromPool(_poolTokenAddress, remainingToBorrowOnPool);
        }

        ERC20(ICToken(_poolTokenAddress).underlying()).safeTransfer(msg.sender, _amount);
    }

    /// @dev Implements withdraw logic.
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
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
        ICToken poolToken = ICToken(_poolTokenAddress);
        uint256 remainingToWithdraw = _amount;

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 supplyPoolIndex = poolToken.exchangeRateCurrent();
            uint256 supplyOnPool = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            uint256 withdrawnInUnderlying = Math.min(
                supplyOnPool.mul(supplyPoolIndex),
                remainingToWithdraw
            );

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                supplyOnPool,
                withdrawnInUnderlying.div(supplyPoolIndex)
            ); // In poolToken
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            if (_isAboveCompoundThreshold(_poolTokenAddress, withdrawnInUnderlying)) {
                _withdrawFromPool(_poolTokenAddress, withdrawnInUnderlying); // Reverts on error
                remainingToWithdraw -= withdrawnInUnderlying;
            }
        }

        /// Transfer withdraw ///

        if (remainingToWithdraw > 0) {
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                remainingToWithdraw.div(marketsManager.supplyP2PExchangeRate(_poolTokenAddress))
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);

            uint256 matched;
            if (
                suppliersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                matched = matchingEngine.matchSuppliersDC(
                    poolToken,
                    remainingToWithdraw,
                    _maxGasToConsume / 2
                );

                if (_isAboveCompoundThreshold(_poolTokenAddress, matched)) {
                    _withdrawFromPool(_poolTokenAddress, matched); // Reverts on error
                    remainingToWithdraw -= matched;
                }
            }

            /// Hard withdraw ///

            if (_isAboveCompoundThreshold(_poolTokenAddress, remainingToWithdraw)) {
                matchingEngine.unmatchBorrowersDC(
                    _poolTokenAddress,
                    remainingToWithdraw,
                    _maxGasToConsume / 2
                );

                _borrowFromPool(_poolTokenAddress, remainingToWithdraw); // Reverts on error
            }
        }

        ERC20(poolToken.underlying()).safeTransfer(_receiver, _amount);

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
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
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

        ICToken poolToken = ICToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.underlying());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowPoolIndex = poolToken.borrowIndex();
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            uint256 repaidInUnderlying = Math.min(
                borrowedOnPool.mul(borrowPoolIndex),
                remainingToRepay
            );

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                remainingToRepay.div(borrowPoolIndex)
            ); // In cdUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            if (repaidInUnderlying > 0) {
                _repayToPool(_poolTokenAddress, underlyingToken, repaidInUnderlying); // Reverts on error
                remainingToRepay -= repaidInUnderlying;
            }
        }

        /// Transfer repay ///

        if (remainingToRepay > 0) {
            uint256 matched;

            borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= Math.min(
                borrowBalanceInOf[_poolTokenAddress][_user].inP2P,
                remainingToRepay.div(marketsManager.borrowP2PExchangeRate(_poolTokenAddress))
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(_poolTokenAddress, _user);

            if (
                borrowersOnPool[_poolTokenAddress].getHead() != address(0) &&
                !marketsManager.noP2P(_poolTokenAddress)
            ) {
                matched = matchingEngine.matchBorrowersDC(
                    poolToken,
                    remainingToRepay,
                    _maxGasToConsume / 2
                );

                if ((_isAboveCompoundThreshold(_poolTokenAddress, matched))) {
                    _repayToPool(_poolTokenAddress, underlyingToken, matched); // Reverts on error
                    remainingToRepay -= matched;
                }
            }

            /// Hard repay ///

            if (remainingToRepay > 0) {
                uint256 toSupply = matchingEngine.unmatchSuppliersDC(
                    _poolTokenAddress,
                    remainingToRepay,
                    _maxGasToConsume / 2
                ); // Reverts on error

                if (_isAboveCompoundThreshold(_poolTokenAddress, toSupply))
                    _supplyToPool(_poolTokenAddress, underlyingToken, toSupply); // Reverts on error
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
    ///@param _poolTokenAddress The address of the pool token to check.
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
    ) internal {
        (uint256 debtValue, uint256 maxDebtValue) = _getUserHypotheticalBalanceStates(
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
    function _getUserHypotheticalBalanceStates(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) internal returns (uint256 debtValue, uint256 maxDebtValue) {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];
            marketsManager.updateP2PExchangeRates(poolTokenEntered);

            // Calling accrueInterest so that computation in getUserLiquidityDataForAsset are the most accurate ones.
            ICToken(poolTokenEntered).accrueInterest();
            AssetLiquidityData memory assetData = getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            unchecked {
                maxDebtValue += assetData.maxDebtValue;
                debtValue += assetData.debtValue;
                ++i;
            }

            if (_poolTokenAddress == poolTokenEntered) {
                debtValue += _borrowedAmount.mul(assetData.underlyingPrice);
                uint256 maxDebtValueSub = _withdrawnAmount.mul(assetData.underlyingPrice).mul(
                    assetData.collateralFactor
                );

                unchecked {
                    maxDebtValue -= maxDebtValue < maxDebtValueSub ? maxDebtValue : maxDebtValueSub;
                }
            }
        }
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
        marketsManager.updateBPYs(_poolTokenAddress);
    }

    /// @dev Withdraws underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(address _poolTokenAddress, uint256 _amount) internal {
        if (ICToken(_poolTokenAddress).redeemUnderlying(_amount) != 0)
            revert RedeemOnCompoundFailed();
        marketsManager.updateBPYs(_poolTokenAddress);
    }

    /// @dev Borrows underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(address _poolTokenAddress, uint256 _amount) internal {
        if ((ICToken(_poolTokenAddress).borrow(_amount) != 0)) revert BorrowOnCompoundFailed();
        marketsManager.updateBPYs(_poolTokenAddress);
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
        marketsManager.updateBPYs(_poolTokenAddress);
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
