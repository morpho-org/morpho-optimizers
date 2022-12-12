// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./interfaces/IEntryPositionsManager.sol";

import "./MorphoUtils.sol";

/// @title EntryPositionsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Morpho's entry points: supply and borrow.
contract EntryPositionsManager is IEntryPositionsManager, MorphoUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using MarketLib for Types.Market;
    using WadRayMath for uint256;
    using Math for uint256;

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
        if (!market.isCreatedMemory()) revert MarketNotCreated();
        if (market.isSupplyPaused) revert SupplyIsPaused();

        _updateIndexes(_poolToken);
        _setSupplying(_onBehalf, borrowMask[_poolToken], true);

        ERC20 underlyingToken = ERC20(market.underlyingToken);
        underlyingToken.safeTransferFrom(_from, address(this), _amount);

        Types.Delta storage delta = deltas[_poolToken];
        Types.SupplyVars memory vars;
        vars.poolBorrowIndex = poolIndexes[_poolToken].poolBorrowIndex;
        vars.remainingToSupply = _amount;

        /// Peer-to-peer supply ///

        // Match the peer-to-peer borrow delta.
        if (delta.p2pBorrowDelta > 0) {
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

        (uint256 inP2P, uint256 onPool) = _supplyBalanceInOf(_poolToken, _onBehalf);

        if (vars.toRepay > 0) {
            uint256 toAddInP2P = vars.toRepay.rayDiv(p2pSupplyIndex[_poolToken]);

            delta.p2pSupplyAmount += toAddInP2P;
            inP2P += toAddInP2P;
            _repayToPool(underlyingToken, vars.toRepay); // Reverts on error.

            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Pool supply ///

        // Supply on pool.
        if (vars.remainingToSupply > 0) {
            onPool += vars.remainingToSupply.rayDiv(poolIndexes[_poolToken].poolSupplyIndex); // In scaled balance.
            _supplyToPool(underlyingToken, vars.remainingToSupply); // Reverts on error.
        }

        _updateSupplierInDS(_poolToken, _onBehalf, onPool, inP2P);

        emit Supplied(_from, _onBehalf, _poolToken, _amount, onPool, inP2P);
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
        if (!market.isCreatedMemory()) revert MarketNotCreated();
        if (market.isBorrowPaused) revert BorrowIsPaused();

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
        if (delta.p2pSupplyDelta > 0) {
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

        (uint256 inP2P, uint256 onPool) = _borrowBalanceInOf(_poolToken, msg.sender);

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.rayDiv(p2pBorrowIndex[_poolToken]); // In peer-to-peer unit.

            delta.p2pBorrowAmount += toAddInP2P;
            inP2P += toAddInP2P;
            emit P2PAmountsUpdated(_poolToken, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            _withdrawFromPool(underlyingToken, _poolToken, toWithdraw); // Reverts on error.
        }

        /// Pool borrow ///

        // Borrow on pool.
        if (remainingToBorrow > 0) {
            onPool += remainingToBorrow.rayDiv(poolIndexes[_poolToken].poolBorrowIndex); // In adUnit.
            _borrowFromPool(underlyingToken, remainingToBorrow);
        }

        _updateBorrowerInDS(_poolToken, msg.sender, onPool, inP2P);
        underlyingToken.safeTransfer(msg.sender, _amount);

        emit Borrowed(msg.sender, _poolToken, _amount, onPool, inP2P);
    }
}
