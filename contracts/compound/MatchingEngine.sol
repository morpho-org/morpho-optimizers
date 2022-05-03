// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./morpho-parts/MorphoGetters.sol";

/// @title MatchingEngine.
/// @notice Smart contract managing the matching engine.
contract MatchingEngine is MorphoGetters {
    using DoubleLinkedList for DoubleLinkedList.List;
    using CompoundMath for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct UnmatchVars {
        uint256 p2pRate;
        uint256 toUnmatch;
        uint256 poolIndex;
        uint256 inUnderlying;
        uint256 gasLeftAtTheBeginning;
    }

    // Struct to avoid stack too deep.
    struct MatchVars {
        uint256 p2pRate;
        uint256 toMatch;
        uint256 poolIndex;
        uint256 inUnderlying;
        uint256 gasLeftAtTheBeginning;
    }

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in P2P after update.
    event SupplierPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the position of a borrower is updated.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    event BorrowerPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// INTERNAL ///

    /// @notice Matches suppliers' liquidity waiting on Compound up to the given `_amount` and move it to P2P.
    /// @dev Note: p2pIndexes must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchSuppliers(
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256 matched) {
        MatchVars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = suppliersOnPool[poolTokenAddress].getHead();
        vars.poolIndex = _poolToken.exchangeRateCurrent();
        vars.p2pRate = p2pSupplyIndex[poolTokenAddress];

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                uint256 onPool = supplyBalanceInOf[poolTokenAddress][user].onPool;
                vars.inUnderlying = onPool.mul(vars.poolIndex);
                unchecked {
                    vars.toMatch = vars.inUnderlying < _amount - matched
                        ? vars.inUnderlying
                        : _amount - matched;
                    matched += vars.toMatch;
                }

                supplyBalanceInOf[poolTokenAddress][user].onPool -= vars.toMatch.div(
                    vars.poolIndex
                );
                supplyBalanceInOf[poolTokenAddress][user].inP2P += vars.toMatch.div(vars.p2pRate); // In peer-to-peer unit
                updateSuppliers(poolTokenAddress, user);
                emit SupplierPositionUpdated(
                    user,
                    poolTokenAddress,
                    supplyBalanceInOf[poolTokenAddress][user].onPool,
                    supplyBalanceInOf[poolTokenAddress][user].inP2P
                );

                user = suppliersOnPool[poolTokenAddress].getHead();
            }
        }
    }

    /// @notice Unmatches suppliers' liquidity in P2P up to the given `_amount` and move it to Compound.
    /// @dev Note: p2pIndexes must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function unmatchSuppliers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        UnmatchVars memory vars;
        address user = suppliersInP2P[_poolTokenAddress].getHead();
        vars.poolIndex = ICToken(_poolTokenAddress).exchangeRateCurrent();
        vars.p2pRate = p2pSupplyIndex[_poolTokenAddress];
        uint256 remainingToUnmatch = _amount; // In underlying

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = supplyBalanceInOf[_poolTokenAddress][user].inP2P.mul(
                    vars.p2pRate
                );
                unchecked {
                    vars.toUnmatch = vars.inUnderlying < remainingToUnmatch
                        ? vars.inUnderlying
                        : remainingToUnmatch; // In underlying
                    remainingToUnmatch -= vars.toUnmatch;
                }

                supplyBalanceInOf[_poolTokenAddress][user].onPool += vars.toUnmatch.div(
                    vars.poolIndex
                );
                supplyBalanceInOf[_poolTokenAddress][user].inP2P -= vars.toUnmatch.div(
                    vars.p2pRate
                ); // In peer-to-peer unit
                updateSuppliers(_poolTokenAddress, user);
                emit SupplierPositionUpdated(
                    user,
                    _poolTokenAddress,
                    supplyBalanceInOf[_poolTokenAddress][user].onPool,
                    supplyBalanceInOf[_poolTokenAddress][user].inP2P
                );

                user = suppliersInP2P[_poolTokenAddress].getHead();
            }
        }

        return _amount - remainingToUnmatch;
    }

    /// @notice Matches borrowers' liquidity waiting on Compound up to the given `_amount` and move it to P2P.
    /// @dev Note: p2pIndexes must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchBorrowers(
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256 matched) {
        MatchVars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = borrowersOnPool[poolTokenAddress].getHead();
        vars.poolIndex = _poolToken.borrowIndex();
        vars.p2pRate = p2pBorrowIndex[poolTokenAddress];

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = borrowBalanceInOf[poolTokenAddress][user].onPool.mul(
                    vars.poolIndex
                );
                unchecked {
                    vars.toMatch = vars.inUnderlying < _amount - matched
                        ? vars.inUnderlying
                        : _amount - matched;
                    matched += vars.toMatch;
                }

                borrowBalanceInOf[poolTokenAddress][user].onPool -= vars.toMatch.div(
                    vars.poolIndex
                );
                borrowBalanceInOf[poolTokenAddress][user].inP2P += vars.toMatch.div(vars.p2pRate);
                updateBorrowers(poolTokenAddress, user);
                emit BorrowerPositionUpdated(
                    user,
                    poolTokenAddress,
                    borrowBalanceInOf[poolTokenAddress][user].onPool,
                    borrowBalanceInOf[poolTokenAddress][user].inP2P
                );

                user = borrowersOnPool[poolTokenAddress].getHead();
            }
        }
    }

    /// @notice Unmatches borrowers' liquidity in P2P for the given `_amount` and move it to Compound.
    /// @dev Note: p2pIndexes must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function unmatchBorrowers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        UnmatchVars memory vars;
        address user = borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;
        vars.poolIndex = ICToken(_poolTokenAddress).borrowIndex();
        vars.p2pRate = p2pBorrowIndex[_poolTokenAddress];

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = borrowBalanceInOf[_poolTokenAddress][user].inP2P.mul(
                    vars.p2pRate
                );
                unchecked {
                    vars.toUnmatch = vars.inUnderlying < remainingToUnmatch
                        ? vars.inUnderlying
                        : remainingToUnmatch; // In underlying
                    remainingToUnmatch -= vars.toUnmatch;
                }

                borrowBalanceInOf[_poolTokenAddress][user].onPool += vars.toUnmatch.div(
                    vars.poolIndex
                );
                borrowBalanceInOf[_poolTokenAddress][user].inP2P -= vars.toUnmatch.div(
                    vars.p2pRate
                );
                updateBorrowers(_poolTokenAddress, user);
                emit BorrowerPositionUpdated(
                    user,
                    _poolTokenAddress,
                    borrowBalanceInOf[_poolTokenAddress][user].onPool,
                    borrowBalanceInOf[_poolTokenAddress][user].inP2P
                );

                user = borrowersInP2P[_poolTokenAddress].getHead();
            }
        }

        return _amount - remainingToUnmatch;
    }

    /// @notice Updates suppliers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function updateSuppliers(address _poolTokenAddress, address _user) internal {
        uint256 onPool = supplyBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_user);

        // Check pool.
        if (onPool <= dustThreshold) {
            supplyBalanceInOf[_poolTokenAddress][_user].onPool = 0;
            onPool = 0;
        }
        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) suppliersOnPool[_poolTokenAddress].remove(_user);
            if (onPool > 0)
                suppliersOnPool[_poolTokenAddress].insertSorted(_user, onPool, maxSortedUsers);
        }

        // Check P2P.
        if (inP2P <= dustThreshold) {
            supplyBalanceInOf[_poolTokenAddress][_user].inP2P = 0;
            inP2P = 0;
        }
        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) suppliersInP2P[_poolTokenAddress].remove(_user);
            if (inP2P > 0)
                suppliersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, maxSortedUsers);
        }

        if (isCompRewardsActive && address(rewardsManager) != address(0))
            rewardsManager.accrueUserSupplyUnclaimedRewards(
                _user,
                _poolTokenAddress,
                formerValueOnPool
            );
    }

    /// @notice Updates borrowers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function updateBorrowers(address _poolTokenAddress, address _user) internal {
        uint256 onPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_user);

        // Check pool.
        if (onPool <= dustThreshold) {
            borrowBalanceInOf[_poolTokenAddress][_user].onPool = 0;
            onPool = 0;
        }
        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) borrowersOnPool[_poolTokenAddress].remove(_user);
            if (onPool > 0)
                borrowersOnPool[_poolTokenAddress].insertSorted(_user, onPool, maxSortedUsers);
        }

        // Check P2P.
        if (inP2P <= dustThreshold) {
            borrowBalanceInOf[_poolTokenAddress][_user].inP2P = 0;
            inP2P = 0;
        }
        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) borrowersInP2P[_poolTokenAddress].remove(_user);
            if (inP2P > 0)
                borrowersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, maxSortedUsers);
        }

        if (isCompRewardsActive && address(rewardsManager) != address(0))
            rewardsManager.accrueUserBorrowUnclaimedRewards(
                _user,
                _poolTokenAddress,
                formerValueOnPool
            );
    }
}
