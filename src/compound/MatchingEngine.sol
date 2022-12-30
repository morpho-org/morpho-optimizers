// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./MorphoUtils.sol";

/// @title MatchingEngine.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Smart contract managing the matching engine.
abstract contract MatchingEngine is MorphoUtils {
    using DoubleLinkedList for DoubleLinkedList.List;
    using CompoundMath for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct UnmatchVars {
        uint256 p2pIndex;
        uint256 toUnmatch;
        uint256 poolIndex;
        uint256 inUnderlying;
        uint256 gasLeftAtTheBeginning;
    }

    // Struct to avoid stack too deep.
    struct MatchVars {
        uint256 p2pIndex;
        uint256 toMatch;
        uint256 poolIndex;
        uint256 inUnderlying;
        uint256 gasLeftAtTheBeginning;
    }

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event SupplierPositionUpdated(
        address indexed _user,
        address indexed _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the position of a borrower is updated.
    /// @param _user The address of the borrower.
    /// @param _poolToken The address of the market.
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update.
    event BorrowerPositionUpdated(
        address indexed _user,
        address indexed _poolToken,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// INTERNAL ///

    /// @notice Matches suppliers' liquidity waiting on Compound up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects Compound's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchSuppliers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = ICToken(_poolToken).exchangeRateStored(); // Exchange rate has already been updated.
        vars.p2pIndex = p2pSupplyIndex[_poolToken];
        address firstPoolSupplier;
        vars.gasLeftAtTheBeginning = gasleft();

        while (
            matched < _amount &&
            (firstPoolSupplier = suppliersOnPool[_poolToken].getHead()) != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            Types.SupplyBalance storage firstPoolSupplierBalance = supplyBalanceInOf[_poolToken][
                firstPoolSupplier
            ];
            vars.inUnderlying = firstPoolSupplierBalance.onPool.mul(vars.poolIndex);

            uint256 poolSupplyBalance;
            uint256 p2pSupplyBalance;
            uint256 maxToMatch = _amount - matched;

            if (vars.inUnderlying <= maxToMatch) {
                // poolSupplyBalance is 0.
                p2pSupplyBalance =
                    firstPoolSupplierBalance.inP2P +
                    vars.inUnderlying.div(vars.p2pIndex);
                matched += vars.inUnderlying;
            } else {
                poolSupplyBalance =
                    firstPoolSupplierBalance.onPool -
                    maxToMatch.div(vars.poolIndex);
                p2pSupplyBalance = firstPoolSupplierBalance.inP2P + maxToMatch.div(vars.p2pIndex);
                matched = _amount;
            }

            firstPoolSupplierBalance.onPool = poolSupplyBalance;
            firstPoolSupplierBalance.inP2P = p2pSupplyBalance;
            _updateSupplierInDS(_poolToken, firstPoolSupplier);

            emit SupplierPositionUpdated(
                firstPoolSupplier,
                _poolToken,
                poolSupplyBalance,
                p2pSupplyBalance
            );
        }

        gasConsumedInMatching = vars.gasLeftAtTheBeginning - gasleft();
    }

    /// @notice Unmatches suppliers' liquidity in peer-to-peer up to the given `_amount` and moves it to Compound.
    /// @dev Note: This function expects Compound's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function _unmatchSuppliers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256) {
        if (_maxGasForMatching == 0) return 0;

        UnmatchVars memory vars;
        vars.poolIndex = ICToken(_poolToken).exchangeRateStored(); // Exchange rate has already been updated.
        vars.p2pIndex = p2pSupplyIndex[_poolToken];
        address firstP2PSupplier;
        uint256 remainingToUnmatch = _amount;
        vars.gasLeftAtTheBeginning = gasleft();

        while (
            remainingToUnmatch > 0 &&
            (firstP2PSupplier = suppliersInP2P[_poolToken].getHead()) != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            Types.SupplyBalance storage firstP2PSupplierBalance = supplyBalanceInOf[_poolToken][
                firstP2PSupplier
            ];
            vars.inUnderlying = firstP2PSupplierBalance.inP2P.mul(vars.p2pIndex);

            uint256 poolSupplyBalance;
            uint256 p2pSupplyBalance;

            if (vars.inUnderlying <= remainingToUnmatch) {
                // p2pSupplyBalance is 0.
                poolSupplyBalance =
                    firstP2PSupplierBalance.onPool +
                    vars.inUnderlying.div(vars.poolIndex);
                remainingToUnmatch -= vars.inUnderlying;
            } else {
                poolSupplyBalance =
                    firstP2PSupplierBalance.onPool +
                    remainingToUnmatch.div(vars.poolIndex);
                p2pSupplyBalance =
                    firstP2PSupplierBalance.inP2P -
                    remainingToUnmatch.div(vars.p2pIndex);
                remainingToUnmatch = 0;
            }

            firstP2PSupplierBalance.onPool = poolSupplyBalance;
            firstP2PSupplierBalance.inP2P = p2pSupplyBalance;
            _updateSupplierInDS(_poolToken, firstP2PSupplier);

            emit SupplierPositionUpdated(
                firstP2PSupplier,
                _poolToken,
                poolSupplyBalance,
                p2pSupplyBalance
            );
        }

        return _amount - remainingToUnmatch;
    }

    /// @notice Matches borrowers' liquidity waiting on Compound up to the given `_amount` and moves it to peer-to-peer.
    /// @dev Note: This function expects stored indexes to have been updated
    /// @param _poolToken The address of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    /// @return gasConsumedInMatching The amount of gas consumed within the matching loop.
    function _matchBorrowers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = lastPoolIndexes[_poolToken].lastBorrowPoolIndex;
        vars.p2pIndex = p2pBorrowIndex[_poolToken];
        address firstPoolBorrower;
        vars.gasLeftAtTheBeginning = gasleft();

        while (
            matched < _amount &&
            (firstPoolBorrower = borrowersOnPool[_poolToken].getHead()) != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            Types.BorrowBalance storage firstPoolBorrowerBalance = borrowBalanceInOf[_poolToken][
                firstPoolBorrower
            ];
            vars.inUnderlying = firstPoolBorrowerBalance.onPool.mul(vars.poolIndex);

            uint256 poolBorrowBalance;
            uint256 p2pBorrowBalance;
            uint256 maxToMatch = _amount - matched;

            if (vars.inUnderlying <= maxToMatch) {
                // poolBorrowBalance is 0.
                p2pBorrowBalance =
                    firstPoolBorrowerBalance.inP2P +
                    vars.inUnderlying.div(vars.p2pIndex);
                matched += vars.inUnderlying;
            } else {
                poolBorrowBalance =
                    firstPoolBorrowerBalance.onPool -
                    maxToMatch.div(vars.poolIndex);
                p2pBorrowBalance = firstPoolBorrowerBalance.inP2P + maxToMatch.div(vars.p2pIndex);
                matched = _amount;
            }

            firstPoolBorrowerBalance.onPool = poolBorrowBalance;
            firstPoolBorrowerBalance.inP2P = p2pBorrowBalance;
            _updateBorrowerInDS(_poolToken, firstPoolBorrower);

            emit BorrowerPositionUpdated(
                firstPoolBorrower,
                _poolToken,
                poolBorrowBalance,
                p2pBorrowBalance
            );
        }

        gasConsumedInMatching = vars.gasLeftAtTheBeginning - gasleft();
    }

    /// @notice Unmatches borrowers' liquidity in peer-to-peer for the given `_amount` and moves it to Compound.
    /// @dev Note: This function expects and peer-to-peer indexes to have been updated.
    /// @param _poolToken The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function _unmatchBorrowers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256) {
        if (_maxGasForMatching == 0) return 0;

        UnmatchVars memory vars;
        vars.poolIndex = lastPoolIndexes[_poolToken].lastBorrowPoolIndex;
        vars.p2pIndex = p2pBorrowIndex[_poolToken];
        address firstP2PBorrower;
        uint256 remainingToUnmatch = _amount;
        vars.gasLeftAtTheBeginning = gasleft();

        while (
            remainingToUnmatch > 0 &&
            (firstP2PBorrower = borrowersInP2P[_poolToken].getHead()) != address(0) &&
            vars.gasLeftAtTheBeginning - gasleft() < _maxGasForMatching
        ) {
            Types.BorrowBalance storage firstP2PBorrowerBalance = borrowBalanceInOf[_poolToken][
                firstP2PBorrower
            ];
            vars.inUnderlying = firstP2PBorrowerBalance.inP2P.mul(vars.p2pIndex);

            uint256 poolBorrowBalance;
            uint256 p2pBorrowBalance;

            if (vars.inUnderlying <= remainingToUnmatch) {
                // p2pBorrowBalance is 0.
                poolBorrowBalance =
                    firstP2PBorrowerBalance.onPool +
                    vars.inUnderlying.div(vars.poolIndex);
                remainingToUnmatch -= vars.inUnderlying;
            } else {
                poolBorrowBalance =
                    firstP2PBorrowerBalance.onPool +
                    remainingToUnmatch.div(vars.poolIndex);
                p2pBorrowBalance =
                    firstP2PBorrowerBalance.inP2P -
                    remainingToUnmatch.div(vars.p2pIndex);
                remainingToUnmatch = 0;
            }

            firstP2PBorrowerBalance.onPool = poolBorrowBalance;
            firstP2PBorrowerBalance.inP2P = p2pBorrowBalance;
            _updateBorrowerInDS(_poolToken, firstP2PBorrower);

            emit BorrowerPositionUpdated(
                firstP2PBorrower,
                _poolToken,
                poolBorrowBalance,
                p2pBorrowBalance
            );
        }

        return _amount - remainingToUnmatch;
    }

    /// @notice Updates the given `_user`'s position in the supplier data structures.
    /// @param _poolToken The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function _updateSupplierInDS(address _poolToken, address _user) internal {
        Types.SupplyBalance storage supplierSupplyBalance = supplyBalanceInOf[_poolToken][_user];
        uint256 onPool = supplierSupplyBalance.onPool;
        uint256 inP2P = supplierSupplyBalance.inP2P;
        DoubleLinkedList.List storage marketSuppliersOnPool = suppliersOnPool[_poolToken];
        DoubleLinkedList.List storage marketSuppliersInP2P = suppliersInP2P[_poolToken];
        uint256 formerValueOnPool = marketSuppliersOnPool.getValueOf(_user);
        uint256 formerValueInP2P = marketSuppliersInP2P.getValueOf(_user);

        // Round pool balance to 0 if below threshold.
        if (onPool <= dustThreshold) {
            supplierSupplyBalance.onPool = 0;
            onPool = 0;
        }
        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) marketSuppliersOnPool.remove(_user);
            if (onPool > 0) marketSuppliersOnPool.insertSorted(_user, onPool, maxSortedUsers);
        }

        // Round peer-to-peer balance to 0 if below threshold.
        if (inP2P <= dustThreshold) {
            supplierSupplyBalance.inP2P = 0;
            inP2P = 0;
        }
        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) marketSuppliersInP2P.remove(_user);
            if (inP2P > 0) marketSuppliersInP2P.insertSorted(_user, inP2P, maxSortedUsers);
        }

        if (address(rewardsManager) != address(0))
            rewardsManager.accrueUserSupplyUnclaimedRewards(_user, _poolToken, formerValueOnPool);
    }

    /// @notice Updates the given `_user`'s position in the borrower data structures.
    /// @param _poolToken The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function _updateBorrowerInDS(address _poolToken, address _user) internal {
        Types.BorrowBalance storage borrowerBorrowBalance = borrowBalanceInOf[_poolToken][_user];
        uint256 onPool = borrowerBorrowBalance.onPool;
        uint256 inP2P = borrowerBorrowBalance.inP2P;
        DoubleLinkedList.List storage marketBorrowersOnPool = borrowersOnPool[_poolToken];
        DoubleLinkedList.List storage marketBorrowersInP2P = borrowersInP2P[_poolToken];
        uint256 formerValueOnPool = marketBorrowersOnPool.getValueOf(_user);
        uint256 formerValueInP2P = marketBorrowersInP2P.getValueOf(_user);

        // Round pool balance to 0 if below threshold.
        if (onPool <= dustThreshold) {
            borrowerBorrowBalance.onPool = 0;
            onPool = 0;
        }
        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) marketBorrowersOnPool.remove(_user);
            if (onPool > 0) marketBorrowersOnPool.insertSorted(_user, onPool, maxSortedUsers);
        }

        // Round peer-to-peer balance to 0 if below threshold.
        if (inP2P <= dustThreshold) {
            borrowerBorrowBalance.inP2P = 0;
            inP2P = 0;
        }
        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) marketBorrowersInP2P.remove(_user);
            if (inP2P > 0) marketBorrowersInP2P.insertSorted(_user, inP2P, maxSortedUsers);
        }

        if (address(rewardsManager) != address(0))
            rewardsManager.accrueUserBorrowUnclaimedRewards(_user, _poolToken, formerValueOnPool);
    }
}
