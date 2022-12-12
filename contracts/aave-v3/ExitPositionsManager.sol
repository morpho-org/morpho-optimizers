// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./interfaces/IExitPositionsManager.sol";

import "./MorphoUtils.sol";

/// @title ExitPositionsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Morpho's exit points: withdraw, repay and liquidate.
contract ExitPositionsManager is IExitPositionsManager, MorphoUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using MarketLib for Types.Market;
    using WadRayMath for uint256;
    using Math for uint256;

    /// LOGIC ///

    /// @dev Implements withdraw logic with security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function withdrawLogic(
        address _poolToken,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        if (_receiver == address(0)) revert AddressIsZero();
        Types.Market memory market = market[_poolToken];
        if (!market.isCreatedMemory()) revert MarketNotCreated();
        if (market.isWithdrawPaused) revert WithdrawIsPaused();

        _updateIndexes(_poolToken);
        uint256 toWithdraw = Math.min(_getUserSupplyBalanceInOf(_poolToken, _supplier), _amount);
        if (toWithdraw == 0) revert UserNotMemberOfMarket();

        if (!_withdrawAllowed(_supplier, _poolToken, toWithdraw)) revert UnauthorisedWithdraw();

        _unsafeWithdrawLogic(_poolToken, toWithdraw, _supplier, _receiver, _maxGasForMatching);
    }

    /// @dev Implements repay logic with security checks.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _repayer The address of the account repaying the debt.
    /// @param _onBehalf The address of the account whose debt is repaid.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function repayLogic(
        address _poolToken,
        address _repayer,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        Types.Market memory market = market[_poolToken];
        if (!market.isCreatedMemory()) revert MarketNotCreated();
        if (market.isRepayPaused) revert RepayIsPaused();

        _updateIndexes(_poolToken);
        uint256 toRepay = Math.min(_getUserBorrowBalanceInOf(_poolToken, _onBehalf), _amount);
        if (toRepay == 0) revert UserNotMemberOfMarket();

        _unsafeRepayLogic(_poolToken, _repayer, _onBehalf, toRepay, _maxGasForMatching);
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowed The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateral The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidateLogic(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external {
        Types.Market memory collateralMarket = market[_poolTokenCollateral];
        if (!collateralMarket.isCreatedMemory()) revert MarketNotCreated();
        if (collateralMarket.isLiquidateCollateralPaused) revert LiquidateCollateralIsPaused();
        Types.Market memory borrowedMarket = market[_poolTokenBorrowed];
        if (!borrowedMarket.isCreatedMemory()) revert MarketNotCreated();
        if (borrowedMarket.isLiquidateBorrowPaused) revert LiquidateBorrowIsPaused();

        if (
            !_isBorrowingAndSupplying(
                userMarkets[_borrower],
                borrowMask[_poolTokenBorrowed],
                borrowMask[_poolTokenCollateral]
            )
        ) revert UserNotMemberOfMarket();

        _updateIndexes(_poolTokenBorrowed);
        _updateIndexes(_poolTokenCollateral);

        Types.LiquidateVars memory vars;
        (vars.liquidationAllowed, vars.closeFactor) = _liquidationAllowed(
            _borrower,
            borrowedMarket.isDeprecated
        );
        if (!vars.liquidationAllowed) revert UnauthorisedLiquidate();

        vars.amountToLiquidate = Math.min(
            _amount,
            _getUserBorrowBalanceInOf(_poolTokenBorrowed, _borrower).percentMul(vars.closeFactor) // Max liquidatable debt.
        );

        IPool poolMem = pool;
        (, , vars.liquidationBonus, vars.collateralReserveDecimals, , ) = poolMem
        .getConfiguration(collateralMarket.underlyingToken)
        .getParams();
        (, , , vars.borrowedReserveDecimals, , ) = poolMem
        .getConfiguration(borrowedMarket.underlyingToken)
        .getParams();

        unchecked {
            vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;
            vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;
        }

        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        vars.borrowedTokenPrice = oracle.getAssetPrice(borrowedMarket.underlyingToken);
        vars.collateralPrice = oracle.getAssetPrice(collateralMarket.underlyingToken);
        vars.amountToSeize = ((vars.amountToLiquidate *
            vars.borrowedTokenPrice *
            vars.collateralTokenUnit) / (vars.borrowedTokenUnit * vars.collateralPrice))
        .percentMul(vars.liquidationBonus);

        vars.collateralBalance = _getUserSupplyBalanceInOf(_poolTokenCollateral, _borrower);

        if (vars.amountToSeize > vars.collateralBalance) {
            vars.amountToSeize = vars.collateralBalance;
            vars.amountToLiquidate = ((vars.collateralBalance *
                vars.collateralPrice *
                vars.borrowedTokenUnit) / (vars.borrowedTokenPrice * vars.collateralTokenUnit))
            .percentDiv(vars.liquidationBonus);
        }

        _unsafeRepayLogic(_poolTokenBorrowed, msg.sender, _borrower, vars.amountToLiquidate, 0);
        _unsafeWithdrawLogic(_poolTokenCollateral, vars.amountToSeize, _borrower, msg.sender, 0);

        emit Liquidated(
            msg.sender,
            _borrower,
            _poolTokenBorrowed,
            vars.amountToLiquidate,
            _poolTokenCollateral,
            vars.amountToSeize
        );
    }

    /// @notice Implements increaseP2PDeltas logic.
    /// @dev The current Morpho supply on the pool might not be enough to borrow `_amount` before resupplying it.
    /// In this case, consider calling this function multiple times.
    /// @param _poolToken The address of the market on which to increase deltas.
    /// @param _amount The maximum amount to add to the deltas (in underlying).
    function increaseP2PDeltasLogic(address _poolToken, uint256 _amount)
        external
        isMarketCreated(_poolToken)
    {
        _updateIndexes(_poolToken);

        Types.Delta storage deltas = deltas[_poolToken];
        Types.PoolIndexes memory poolIndexes = poolIndexes[_poolToken];

        _amount = Math.min(
            _amount,
            Math.min(
                deltas.p2pSupplyAmount.rayMul(p2pSupplyIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pSupplyDelta.rayMul(poolIndexes.poolSupplyIndex)
                ),
                deltas.p2pBorrowAmount.rayMul(p2pBorrowIndex[_poolToken]).zeroFloorSub(
                    deltas.p2pBorrowDelta.rayMul(poolIndexes.poolBorrowIndex)
                )
            )
        );
        if (_amount == 0) revert AmountIsZero();

        deltas.p2pSupplyDelta += _amount.rayDiv(poolIndexes.poolSupplyIndex);
        deltas.p2pBorrowDelta += _amount.rayDiv(poolIndexes.poolBorrowIndex);
        emit P2PSupplyDeltaUpdated(_poolToken, deltas.p2pSupplyDelta);
        emit P2PBorrowDeltaUpdated(_poolToken, deltas.p2pBorrowDelta);

        ERC20 underlyingToken = ERC20(market[_poolToken].underlyingToken);
        _borrowFromPool(underlyingToken, _amount);
        _supplyToPool(underlyingToken, _amount);

        emit P2PDeltasIncreased(_poolToken, _amount);
    }
}
