// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IPositionsManager.sol";

import "./MatchingEngine.sol";

/// @title PositionsManager.
/// @notice Main Logic of Morpho Protocol, implementation of the 5 main functionalities: supply, borrow, withdraw, repay and liquidate.
contract PositionsManager is IPositionsManager, MatchingEngine {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using DoubleLinkedList for DoubleLinkedList.List;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using Math for uint256;

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

    /// @notice Thrown when the amount of collateral to seize is above the collateral amount.
    error ToSeizeAboveCollateral();

    /// @notice Thrown when user is not a member of the market.
    error UserNotMemberOfMarket();

    /// @notice Thrown when the user does not have enough remaining collateral to withdraw.
    error UnauthorisedWithdraw();

    /// @notice Thrown when the positions of the user is not liquidable.
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
        uint256 onPoolSupply;
        uint256 withdrawable;
        uint256 toWithdraw;
    }

    // Struct to avoid stack too deep.
    struct RepayVars {
        uint256 maxGasForMatching;
        uint256 remainingToRepay;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 toRepay;
    }

    // Struct to avoid stack too deep.
    struct LiquidateVars {
        uint256 borrowedPrice; // The price of the asset borrowed (in ETH).
        uint256 collateralPrice; // The price of the collateral asset (in ETH).
        uint256 supplyBalance; // The total of collateral of the user (in underlying).
        uint256 amountToSeize; // The amount of collateral the liquidator can seize (in underlying).
        uint256 liquidationBonus; // The liquidation bonus on Aave.
        uint256 collateralReserveDecimals; // The number of decimals of the collateral asset in the reserve.
        uint256 collateralTokenUnit; // The collateral token unit considering its decimals.
        uint256 borrowedReserveDecimals; // The number of decimals of the borrowed asset in the reserve.
        uint256 borrowedTokenUnit; // The unit of borrowed token considering its decimals.
        uint256 amountToLiquidate; // The amount of tokens to liquidate (in underlying).
        uint256 maxLiquidatableDebt; // The maximum amount of debt tokens liquidatable (in underlying).
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
        updateP2PIndexes(_poolTokenAddress);

        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolBorrowIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        uint256 remainingToSupply = _amount;
        uint256 toRepay;

        /// Supply in peer-to-peer ///

        // Match borrow peer-to-peer delta first if any.
        if (delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(poolBorrowIndex),
                remainingToSupply
            );

            toRepay += matchedDelta;
            remainingToSupply -= matchedDelta;
            delta.p2pBorrowDelta -= matchedDelta.rayDiv(poolBorrowIndex);
            emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
        }

        if (
            remainingToSupply > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            borrowersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            // Match pool suppliers if any.
            (uint256 matched, ) = _matchBorrowers(
                _poolTokenAddress,
                underlyingToken,
                remainingToSupply,
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                toRepay += matched;
                remainingToSupply -= matched;
                delta.p2pBorrowAmount += matched.rayDiv(p2pBorrowIndex[_poolTokenAddress]);
            }
        }

        if (toRepay > 0) {
            uint256 toAddInP2P = toRepay.rayDiv(p2pSupplyIndex[_poolTokenAddress]);

            delta.p2pSupplyAmount += toAddInP2P;
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            _updateSupplierInDS(_poolTokenAddress, msg.sender);

            toRepay = Math.min(
                toRepay,
                IVariableDebtToken(
                    lendingPool.getReserveData(address(underlyingToken)).variableDebtTokenAddress
                ).scaledBalanceOf(address(this))
                .rayMul(poolBorrowIndex) // The debt of the contract.
            );

            if (toRepay > 0) _repayToPool(underlyingToken, toRepay); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Supply on pool ///

        if (remainingToSupply > 0) {
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToSupply.rayDiv(
                lendingPool.getReserveNormalizedIncome(address(underlyingToken))
            ); // In scaled balance.
            _supplyToPool(underlyingToken, remainingToSupply); // Reverts on error.
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
        updateP2PIndexes(_poolTokenAddress);

        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        if (!_borrowAllowed(msg.sender, _poolTokenAddress, 0, _amount)) revert UnauthorisedBorrow();

        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolSupplyIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        uint256 withdrawable = IAToken(_poolTokenAddress).balanceOf(address(this)); // The balance on pool.

        /// Borrow in peer-to-peer ///

        // Match supply peer-to-peer delta first if any.
        if (delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.rayMul(poolSupplyIndex),
                remainingToBorrow,
                withdrawable
            );

            toWithdraw += matchedDelta;
            remainingToBorrow -= matchedDelta;
            delta.p2pSupplyDelta -= matchedDelta.rayDiv(poolSupplyIndex);
            emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pSupplyDelta);
        }

        if (
            remainingToBorrow > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            suppliersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            // Match pool suppliers if any.
            (uint256 matched, ) = _matchSuppliers(
                _poolTokenAddress,
                underlyingToken,
                Math.min(remainingToBorrow, withdrawable - toWithdraw),
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                toWithdraw += matched;
                remainingToBorrow -= matched;
                deltas[_poolTokenAddress].p2pSupplyAmount += matched.rayDiv(
                    p2pSupplyIndex[_poolTokenAddress]
                );
            }
        }

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.rayDiv(p2pBorrowIndex[_poolTokenAddress]); // In peer-to-peer unit.

            deltas[_poolTokenAddress].p2pBorrowAmount += toAddInP2P;
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            if (toWithdraw > 0) _withdrawFromPool(underlyingToken, toWithdraw); // Reverts on error.
        }

        /// Borrow on pool ///

        if (remainingToBorrow > 0) {
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrow.rayDiv(
                lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))
            ); // In adUnit.
            _borrowFromPool(underlyingToken, remainingToBorrow);
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

        updateP2PIndexes(_poolTokenAddress);
        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(_poolTokenAddress, _supplier),
            _amount
        );

        if (!_withdrawAllowed(_supplier, _poolTokenAddress, toWithdraw, 0))
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

        updateP2PIndexes(_poolTokenAddress);
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

        updateP2PIndexes(_poolTokenBorrowedAddress);
        updateP2PIndexes(_poolTokenCollateralAddress);

        if (!_liquidationAllowed(_borrower)) revert UnauthorisedLiquidate();

        LiquidateVars memory vars;
        address tokenBorrowedAddress = IAToken(_poolTokenBorrowedAddress)
        .UNDERLYING_ASSET_ADDRESS();

        vars.maxLiquidatableDebt = _getUserBorrowBalanceInOf(_poolTokenBorrowedAddress, _borrower)
        .percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);

        vars.amountToLiquidate = Math.min(_amount, vars.maxLiquidatableDebt);

        address tokenCollateralAddress = IAToken(_poolTokenCollateralAddress)
        .UNDERLYING_ASSET_ADDRESS();

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        vars.borrowedPrice = oracle.getAssetPrice(tokenBorrowedAddress); // In ETH.
        vars.collateralPrice = oracle.getAssetPrice(tokenCollateralAddress); // In ETH.

        (, , vars.liquidationBonus, vars.collateralReserveDecimals, ) = lendingPool
        .getConfiguration(tokenCollateralAddress)
        .getParamsMemory();
        (, , , vars.borrowedReserveDecimals, ) = lendingPool
        .getConfiguration(tokenBorrowedAddress)
        .getParamsMemory();

        unchecked {
            vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;
            vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;
        }

        vars.amountToSeize = ((vars.amountToLiquidate *
            vars.borrowedPrice *
            vars.collateralTokenUnit) / (vars.borrowedTokenUnit * vars.collateralPrice))
        .percentMul(vars.liquidationBonus); // Same mechanism as Aave.

        vars.supplyBalance = _getUserSupplyBalanceInOf(_poolTokenCollateralAddress, _borrower);

        if (vars.amountToSeize > vars.supplyBalance) revert ToSeizeAboveCollateral();

        _safeRepayLogic(_poolTokenBorrowedAddress, _borrower, vars.amountToLiquidate, 0);
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
            vars.amountToLiquidate,
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
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.withdrawable = poolToken.balanceOf(address(this));
        vars.poolSupplyIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));

        /// Soft withdraw ///

        vars.onPoolSupply = supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
        if (vars.onPoolSupply > 0) {
            vars.toWithdraw = Math.min(
                vars.onPoolSupply.rayMul(vars.poolSupplyIndex),
                vars.remainingToWithdraw,
                vars.withdrawable
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -= Math.min(
                vars.onPoolSupply,
                vars.toWithdraw.rayDiv(vars.poolSupplyIndex)
            );
            _updateSupplierInDS(_poolTokenAddress, _supplier);

            if (vars.remainingToWithdraw == 0) {
                _leaveMarketIfNeeded(_poolTokenAddress, _supplier);
                if (vars.toWithdraw > 0) {
                    _withdrawFromPool(underlyingToken, vars.toWithdraw); // Reverts on error.
                    (
                        uint256 totalCollateralETH,
                        uint256 totalDebtETH,
                        ,
                        uint256 currentLiquidationThreshold,
                        ,
                        uint256 healthFactor
                    ) = lendingPool.getUserAccountData(address(this));
                    console.log("totalCollateralETH 2", totalCollateralETH);
                    console.log("totalDebtETH 2", totalDebtETH);
                    console.log("currentLiquidationThreshold 2", currentLiquidationThreshold);
                    console.log("healthFactor 2", healthFactor);
                }
                underlyingToken.safeTransfer(_receiver, _amount);
                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pSupplyIndex[_poolTokenAddress];

        supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= Math.min(
            supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
            vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex)
        ); // In peer-to-peer supply unit.
        _updateSupplierInDS(_poolTokenAddress, _supplier);

        /// Transfer withdraw ///

        // Match peer-to-peer supply delta first if any.
        if (vars.remainingToWithdraw > 0 && delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.rayMul(vars.poolSupplyIndex),
                vars.remainingToWithdraw,
                vars.withdrawable - vars.toWithdraw
            );

            vars.toWithdraw += matchedDelta;
            vars.remainingToWithdraw -= matchedDelta;
            delta.p2pSupplyDelta -= matchedDelta.rayDiv(vars.poolSupplyIndex);
            delta.p2pSupplyAmount -= matchedDelta.rayDiv(vars.p2pSupplyIndex);
            emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pSupplyDelta);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        if (
            vars.remainingToWithdraw > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            suppliersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            // Match pool suppliers if any.
            (uint256 matched, uint256 gasConsumedInMatching) = _matchSuppliers(
                _poolTokenAddress,
                underlyingToken,
                Math.min(vars.remainingToWithdraw, vars.withdrawable - vars.toWithdraw),
                vars.maxGasForMatching
            );
            if (vars.maxGasForMatching <= gasConsumedInMatching) vars.maxGasForMatching = 0;
            else vars.maxGasForMatching -= gasConsumedInMatching;

            if (matched > 0) {
                vars.remainingToWithdraw -= matched;
                vars.toWithdraw += matched;
            }
        }

        if (vars.toWithdraw > 0) _withdrawFromPool(underlyingToken, vars.toWithdraw); // Reverts on error.

        /// Hard withdraw ///

        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = _unmatchBorrowers(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                _maxGasForMatching
            );

            // If unmatched does not cover remainingToWithdraw, the difference is added to the borrow peer-to-peer delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.p2pBorrowDelta += (vars.remainingToWithdraw - unmatched).rayDiv(
                    lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken))
                );
                emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowAmount);
            }

            delta.p2pSupplyAmount -= vars.remainingToWithdraw.rayDiv(vars.p2pSupplyIndex);
            delta.p2pBorrowAmount -= unmatched.rayDiv(p2pBorrowIndex[_poolTokenAddress]);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _borrowFromPool(underlyingToken, vars.remainingToWithdraw); // Reverts on error.
        }

        _leaveMarketIfNeeded(_poolTokenAddress, _supplier);
        underlyingToken.safeTransfer(_receiver, _amount);

        emit Withdrawn(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
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
        IAToken poolToken = IAToken(_poolTokenAddress);
        ERC20 underlyingToken = ERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.maxGasForMatching = _maxGasForMatching;
        vars.poolBorrowIndex = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );

        /// Soft repay ///

        if (borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowedOnPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            vars.toRepay = Math.min(
                borrowedOnPool.rayMul(vars.poolBorrowIndex),
                vars.remainingToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            borrowBalanceInOf[_poolTokenAddress][_user].onPool -= Math.min(
                borrowedOnPool,
                vars.toRepay.rayDiv(vars.poolBorrowIndex)
            ); // In adUnit.
            _updateBorrowerInDS(_poolTokenAddress, _user);

            if (vars.remainingToRepay == 0) {
                // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
                vars.toRepay = Math.min(
                    vars.toRepay,
                    IVariableDebtToken(
                        lendingPool
                        .getReserveData(address(underlyingToken))
                        .variableDebtTokenAddress
                    ).scaledBalanceOf(address(this))
                    .rayMul(vars.poolBorrowIndex) // The debt of the contract.
                );
                if (vars.toRepay > 0) _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.
                _leaveMarketIfNeeded(_poolTokenAddress, _user);
                return;
            }
        }

        Types.Delta storage delta = deltas[_poolTokenAddress];
        vars.p2pSupplyIndex = p2pBorrowIndex[_poolTokenAddress];
        vars.p2pBorrowIndex = p2pSupplyIndex[_poolTokenAddress];
        vars.poolSupplyIndex = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        borrowBalanceInOf[_poolTokenAddress][_user].inP2P -= Math.min(
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P,
            vars.remainingToRepay.rayDiv(vars.p2pSupplyIndex)
        ); // In peer-to-peer borrow unit.
        _updateBorrowerInDS(_poolTokenAddress, _user);

        /// Fee repay ///

        uint256 feeToRepay = Math.min(
            (delta.p2pBorrowAmount.rayMul(vars.p2pBorrowIndex) -
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex)) -
                (delta.p2pSupplyAmount.rayMul(vars.p2pSupplyIndex) -
                    delta.p2pSupplyDelta.rayMul(vars.poolSupplyIndex)),
            vars.remainingToRepay
        );
        vars.remainingToRepay -= feeToRepay;

        /// Transfer repay ///

        // Match peer-to-peer borrow delta first if any.
        if (vars.remainingToRepay > 0 && delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex),
                vars.remainingToRepay
            );

            vars.toRepay += matchedDelta;
            vars.remainingToRepay -= matchedDelta;
            delta.p2pBorrowDelta -= matchedDelta.rayDiv(vars.poolBorrowIndex);
            delta.p2pBorrowAmount -= matchedDelta.rayDiv(vars.p2pSupplyIndex);
            emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        if (
            vars.remainingToRepay > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            borrowersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            // Match pool borrowers if any.
            (uint256 matched, uint256 gasConsumedInMatching) = _matchBorrowers(
                _poolTokenAddress,
                underlyingToken,
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

        // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
        vars.toRepay = Math.min(
            vars.toRepay,
            IVariableDebtToken(
                lendingPool.getReserveData(address(underlyingToken)).variableDebtTokenAddress
            ).scaledBalanceOf(address(this))
            .rayMul(vars.poolBorrowIndex) // The debt of the contract.
        );

        if (vars.toRepay > 0) _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

        /// Hard repay ///

        if (vars.remainingToRepay > 0) {
            uint256 unmatched = _unmatchSuppliers(
                _poolTokenAddress,
                vars.remainingToRepay,
                vars.maxGasForMatching
            );

            // If unmatched does not cover remainingToRepay, the difference is added to the supply peer-to-peer delta.
            if (unmatched < vars.remainingToRepay) {
                delta.p2pSupplyDelta += (vars.remainingToRepay - unmatched).rayDiv(
                    vars.poolSupplyIndex
                );
                emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
            }

            delta.p2pSupplyAmount -= unmatched.rayDiv(vars.p2pBorrowIndex);
            delta.p2pBorrowAmount -= vars.remainingToRepay.rayDiv(vars.p2pSupplyIndex);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _supplyToPool(underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        _leaveMarketIfNeeded(_poolTokenAddress, _user);

        emit Repaid(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
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
    function _repayToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeApprove(address(lendingPool), _amount);
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
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
