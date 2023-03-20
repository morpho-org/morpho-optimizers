// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./interfaces/IEntryPositionsManager.sol";

import "./PositionsManagerUtils.sol";

/// @title EntryPositionsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Morpho's entry points: supply and borrow.
contract EntryPositionsManager is IEntryPositionsManager, PositionsManagerUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;
    using Math for uint256;

    /// EVENTS ///

    /// @notice Emitted when a supply happens.
    /// @param _from The address of the account sending funds.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _poolToken The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Supplied(
        address indexed _from,
        address indexed _onBehalf,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a borrow happens.
    /// @param _borrower The address of the borrower.
    /// @param _poolToken The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update
    event Borrowed(
        address indexed _borrower,
        address indexed _poolToken,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// ERRORS ///

    /// @notice Thrown when borrowing is impossible, because it is not enabled on pool for this specific market.
    error BorrowingNotEnabled();

    /// @notice Thrown when the user does not have enough collateral for the borrow.
    error UnauthorisedBorrow();

    /// @notice Thrown when someone tries to supply but the supply is paused.
    error SupplyIsPaused();

    /// @notice Thrown when someone tries to borrow but the borrow is paused.
    error BorrowIsPaused();

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct SupplyVars {
        uint256 remainingToSupply;
        uint256 poolBorrowIndex;
        uint256 toRepay;
    }

    /// LOGIC ///

    /// @dev Implements supply logic.
    /// @param _poolToken The address of the pool token the user wants to interact with.
    /// @param _from The address of the account sending funds.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function supplyLogic(
        address _poolToken,
        address _from,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_onBehalf == address(0)) revert AddressIsZero();
        if (_amount == 0) revert AmountIsZero();
        Types.Market memory market = market[_poolToken];
        ERC20 underlyingToken = ERC20(market.underlyingToken);

        if (!market.isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isSupplyPaused) revert SupplyIsPaused();

        _updateIndexes(_poolToken);
        _setSupplying(_onBehalf, borrowMask[_poolToken], true);

        underlyingToken.safeTransferFrom(_from, address(this), _amount);

        Types.Delta storage delta = deltas[_poolToken];
        SupplyVars memory vars;
        vars.poolBorrowIndex = poolIndexes[_poolToken].poolBorrowIndex;
        vars.remainingToSupply = _amount;

        /// Peer-to-peer supply ///

        // Match the peer-to-peer borrow delta.
        if (delta.p2pBorrowDelta > 0 && !market.isP2PDisabled) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex),
                vars.remainingToSupply
            ); // In underlying.

            delta.p2pBorrowDelta = delta.p2pBorrowDelta.zeroFloorSub(
                vars.remainingToSupply.rayDiv(vars.poolBorrowIndex)
            );
            vars.toRepay += matchedDelta;
            vars.remainingToSupply -= matchedDelta;
            emit P2PBorrowDeltaUpdated(_poolToken, delta.p2pBorrowDelta);
        }

        // Promote pool borrowers.
        if (
            vars.remainingToSupply > 0 &&
            !market.isP2PDisabled &&
            borrowersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchBorrowers(
                _poolToken,
                vars.remainingToSupply,
                _maxGasForMatching
            ); // In underlying.

            vars.toRepay += matched;
            vars.remainingToSupply -= matched;
            delta.p2pBorrowAmount += matched.rayDiv(p2pBorrowIndex[_poolToken]);
        }

        Types.SupplyBalance storage supplierSupplyBalance = supplyBalanceInOf[_poolToken][
            _onBehalf
        ];

        if (vars.toRepay > 0) {
            uint256 toAddInP2P = vars.toRepay.rayDiv(p2pSupplyIndex[_poolToken]);

            delta.p2pSupplyAmount += toAddInP2P;
            supplierSupplyBalance.inP2P += toAddInP2P;
            _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Pool supply ///

        // Supply on pool.
        if (vars.remainingToSupply > 0) {
            supplierSupplyBalance.onPool += vars.remainingToSupply.rayDiv(
                poolIndexes[_poolToken].poolSupplyIndex
            ); // In scaled balance.
            _supplyToPool(underlyingToken, vars.remainingToSupply); // Reverts on error.
        }

        _updateSupplierInDS(_poolToken, _onBehalf);

        emit Supplied(
            _from,
            _onBehalf,
            _poolToken,
            _amount,
            supplierSupplyBalance.onPool,
            supplierSupplyBalance.inP2P
        );
    }

    /// @dev Implements borrow logic.
    /// @param _poolToken The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function borrowLogic(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        Types.Market memory market = market[_poolToken];
        if (!market.isCreated) revert MarketNotCreated();
        if (marketPauseStatus[_poolToken].isBorrowPaused) revert BorrowIsPaused();

        ERC20 underlyingToken = ERC20(market.underlyingToken);
        if (!pool.getConfiguration(address(underlyingToken)).getBorrowingEnabled())
            revert BorrowingNotEnabled();

        _updateIndexes(_poolToken);
        _setBorrowing(msg.sender, borrowMask[_poolToken], true);

        if (!_borrowAllowed(msg.sender, _poolToken, _amount)) revert UnauthorisedBorrow();

        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Types.Delta storage delta = deltas[_poolToken];
        uint256 poolSupplyIndex = poolIndexes[_poolToken].poolSupplyIndex;

        /// Peer-to-peer borrow ///

        // Match the peer-to-peer supply delta.
        if (delta.p2pSupplyDelta > 0 && !market.isP2PDisabled) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.rayMul(poolSupplyIndex),
                remainingToBorrow
            ); // In underlying.

            delta.p2pSupplyDelta = delta.p2pSupplyDelta.zeroFloorSub(
                remainingToBorrow.rayDiv(poolSupplyIndex)
            );
            toWithdraw += matchedDelta;
            remainingToBorrow -= matchedDelta;
            emit P2PSupplyDeltaUpdated(_poolToken, delta.p2pSupplyDelta);
        }

        // Promote pool suppliers.
        if (
            remainingToBorrow > 0 &&
            !market.isP2PDisabled &&
            suppliersOnPool[_poolToken].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchSuppliers(
                _poolToken,
                remainingToBorrow,
                _maxGasForMatching
            ); // In underlying.

            toWithdraw += matched;
            remainingToBorrow -= matched;
            delta.p2pSupplyAmount += matched.rayDiv(p2pSupplyIndex[_poolToken]);
        }

        Types.BorrowBalance storage borrowerBorrowBalance = borrowBalanceInOf[_poolToken][
            msg.sender
        ];

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.rayDiv(p2pBorrowIndex[_poolToken]); // In peer-to-peer unit.

            delta.p2pBorrowAmount += toAddInP2P;
            borrowerBorrowBalance.inP2P += toAddInP2P;
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _withdrawFromPool(underlyingToken, _poolToken, toWithdraw); // Reverts on error.
        }

        /// Pool borrow ///

        // Borrow on pool.
        if (remainingToBorrow > 0) {
            borrowerBorrowBalance.onPool += remainingToBorrow.rayDiv(
                poolIndexes[_poolToken].poolBorrowIndex
            ); // In adUnit.
            _borrowFromPool(underlyingToken, remainingToBorrow);
        }

        _updateBorrowerInDS(_poolToken, msg.sender);
        underlyingToken.safeTransfer(msg.sender, _amount);

        emit Borrowed(
            msg.sender,
            _poolToken,
            _amount,
            borrowerBorrowBalance.onPool,
            borrowerBorrowBalance.inP2P
        );
    }

    /// @dev Checks whether the user can borrow or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolToken The market to hypothetically borrow in.
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return Whether the borrow is allowed or not.
    function _borrowAllowed(
        address _user,
        address _poolToken,
        uint256 _borrowedAmount
    ) internal returns (bool) {
        Types.LiquidityData memory values = _liquidityData(_user, _poolToken, 0, _borrowedAmount);
        return values.debtEth <= values.borrowableEth;
    }
}
