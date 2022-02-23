// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./PositionsManagerForAaveGettersSetters.sol";
import "../libraries/MatchingEngineFns.sol";

/// @title PositionsManagerForAaveCore.
/// @notice Main Logic of Morpho Protocol, implementation of the 5 main functionalities: supply, borrow, withdraw, repay, liquidate.
contract PositionsManagerForAaveCore is PositionsManagerForAaveGettersSetters {
    using MatchingEngineFns for IMatchingEngineForAave;
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    /// Internal ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) internal {
        _handleMembership(_poolTokenAddress, msg.sender);
        marketsManager.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
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
            _supplyERC20ToPool(_poolTokenAddress, underlyingToken, remainingToSupplyToPool); // Revert on error
        }

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the markets the user wants to enter.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function _borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) internal {
        _handleMembership(_poolTokenAddress, msg.sender);
        _checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        marketsManager.updateRates(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
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
            _borrowERC20FromPool(_poolTokenAddress, underlyingToken, remainingToBorrowOnPool);
        }

        underlyingToken.safeTransfer(msg.sender, _amount);
        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
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
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        _checkUserLiquidity(_supplier, _poolTokenAddress, _amount, 0);
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToWithdraw = _amount;

        /// Soft withdraw ///

        if (supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            uint256 onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            uint256 onPoolSupplyInUnderlying = onPoolSupply.mulWadByRay(normalizedIncome);
            uint256 withdrawnInUnderlying = Math.min(
                Math.min(onPoolSupplyInUnderlying, remainingToWithdraw),
                poolToken.balanceOf(address(this))
            );

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                onPoolSupply,
                withdrawnInUnderlying.divWadByRay(normalizedIncome)
            ); // In poolToken
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);
            if (withdrawnInUnderlying > 0)
                _withdrawERC20FromPool(_poolTokenAddress, underlyingToken, withdrawnInUnderlying); // Revert on error
            remainingToWithdraw -= withdrawnInUnderlying;
        }

        /// Transfer withdraw ///

        if (remainingToWithdraw > 0) {
            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);

            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
                supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                remainingToWithdraw.divWadByRay(supplyP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateSuppliersDC(_poolTokenAddress, _supplier);
            uint256 matchedSupply = matchingEngine.matchSuppliersDC(
                poolToken,
                underlyingToken,
                remainingToWithdraw,
                _maxGasToConsume
            );

            /// Hard withdraw ///

            if (remainingToWithdraw > matchedSupply)
                matchingEngine.unmatchBorrowersDC(
                    _poolTokenAddress,
                    remainingToWithdraw - matchedSupply,
                    _maxGasToConsume
                );
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

    /// @notice Implements repay logic.
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
    ) internal isMarketCreated(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();

        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 remainingToRepay = _amount;

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            address poolTokenAddress = address(poolToken);
            uint256 borrowedOnPool = borrowBalanceInOf[poolTokenAddress][_user].onPool;
            uint256 borrowedOnPoolInUnderlying = borrowedOnPool.mulWadByRay(normalizedVariableDebt);
            uint256 repaidInUnderlying = Math.min(borrowedOnPoolInUnderlying, remainingToRepay);

            borrowBalanceInOf[poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                repaidInUnderlying.divWadByRay(normalizedVariableDebt)
            ); // In adUnit
            matchingEngine.updateBorrowersDC(poolTokenAddress, _user);
            if (repaidInUnderlying > 0)
                _repayERC20ToPool(
                    _poolTokenAddress,
                    underlyingToken,
                    repaidInUnderlying,
                    normalizedVariableDebt
                ); // Revert on error
            remainingToRepay -= repaidInUnderlying;
        }

        /// Transfer repay ///

        if (remainingToRepay > 0) {
            address poolTokenAddress = address(poolToken);
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(poolTokenAddress);

            borrowBalanceInOf[poolTokenAddress][_user].inP2P -= Math.min(
                borrowBalanceInOf[poolTokenAddress][_user].inP2P,
                remainingToRepay.divWadByRay(borrowP2PExchangeRate)
            ); // In p2pUnit
            matchingEngine.updateBorrowersDC(poolTokenAddress, _user);
            uint256 matchedBorrow = matchingEngine.matchBorrowersDC(
                poolToken,
                underlyingToken,
                remainingToRepay,
                _maxGasToConsume
            );

            /// Hard repay ///

            if (_amount > matchedBorrow)
                matchingEngine.unmatchSuppliersDC(
                    poolTokenAddress,
                    remainingToRepay - matchedBorrow,
                    _maxGasToConsume
                ); // Revert on error
        }

        emit Repaid(
            _user,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][_user].onPool,
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P
        );
    }
}
