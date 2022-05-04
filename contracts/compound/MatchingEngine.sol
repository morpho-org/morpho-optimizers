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

    /// @notice Matches suppliers' liquidity waiting on Compound up to the given `_amount` and moves it to P2P.
    /// @dev Note: This function expects Compound's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolTokenAddress The address of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function _matchSuppliers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256 matched) {
        MatchVars memory vars;
        vars.poolIndex = ICToken(_poolTokenAddress).exchangeRateStored(); // Exchange rate has already been updated.
        vars.p2pIndex = p2pSupplyIndex[_poolTokenAddress];
        address firstPoolSupplier = suppliersOnPool[_poolTokenAddress].getHead();

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                firstPoolSupplier != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier]
                .onPool
                .mul(vars.poolIndex);
                unchecked {
                    vars.toMatch = vars.inUnderlying < _amount - matched
                        ? vars.inUnderlying
                        : _amount - matched;
                    matched += vars.toMatch;
                }

                supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].onPool -= vars.toMatch.div(
                    vars.poolIndex
                ); // In cToken.
                supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].inP2P += vars.toMatch.div(
                    vars.p2pIndex
                ); // In peer-to-peer unit.
                _updateSuppliers(_poolTokenAddress, firstPoolSupplier);
                emit SupplierPositionUpdated(
                    firstPoolSupplier,
                    _poolTokenAddress,
                    supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].onPool,
                    supplyBalanceInOf[_poolTokenAddress][firstPoolSupplier].inP2P
                );

                firstPoolSupplier = suppliersOnPool[_poolTokenAddress].getHead();
            }
        }
    }

    /// @notice Unmatches suppliers' liquidity in P2P up to the given `_amount` and moves it to Compound.
    /// @dev Note: This function expects Compound's exchange rate and peer-to-peer indexes to have been updated.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function _unmatchSuppliers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        UnmatchVars memory vars;
        vars.poolIndex = ICToken(_poolTokenAddress).exchangeRateStored(); // Exchange rate has already been updated.
        vars.p2pIndex = p2pSupplyIndex[_poolTokenAddress];
        address firstP2PSupplier = suppliersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                firstP2PSupplier != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier]
                .inP2P
                .mul(vars.p2pIndex);
                unchecked {
                    vars.toUnmatch = vars.inUnderlying < remainingToUnmatch
                        ? vars.inUnderlying
                        : remainingToUnmatch;
                    remainingToUnmatch -= vars.toUnmatch;
                }

                supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].onPool += vars.toUnmatch.div(
                    vars.poolIndex
                ); // In cToken.
                supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].inP2P -= vars.toUnmatch.div(
                    vars.p2pIndex
                ); // In peer-to-peer unit.
                _updateSuppliers(_poolTokenAddress, firstP2PSupplier);
                emit SupplierPositionUpdated(
                    firstP2PSupplier,
                    _poolTokenAddress,
                    supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].onPool,
                    supplyBalanceInOf[_poolTokenAddress][firstP2PSupplier].inP2P
                );

                firstP2PSupplier = suppliersInP2P[_poolTokenAddress].getHead();
            }
        }

        return _amount - remainingToUnmatch;
    }

    /// @notice Matches borrowers' liquidity waiting on Compound up to the given `_amount` and moves it to P2P
    /// @dev Note: This function expects peer-to-peer indexes to have been updated..
    /// @param _poolTokenAddress The address of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function _matchBorrowers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256 matched) {
        MatchVars memory vars;
        vars.poolIndex = ICToken(_poolTokenAddress).borrowIndex();
        vars.p2pIndex = p2pBorrowIndex[_poolTokenAddress];
        address firstPoolBorrower = borrowersOnPool[_poolTokenAddress].getHead();

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                firstPoolBorrower != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower]
                .onPool
                .mul(vars.poolIndex);
                unchecked {
                    vars.toMatch = vars.inUnderlying < _amount - matched
                        ? vars.inUnderlying
                        : _amount - matched;
                    matched += vars.toMatch;
                }

                borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].onPool -= vars.toMatch.div(
                    vars.poolIndex
                ); // In cdUnit.
                borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].inP2P += vars.toMatch.div(
                    vars.p2pIndex
                ); // In peer-to-peer unit.
                _updateBorrowers(_poolTokenAddress, firstPoolBorrower);
                emit BorrowerPositionUpdated(
                    firstPoolBorrower,
                    _poolTokenAddress,
                    borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].onPool,
                    borrowBalanceInOf[_poolTokenAddress][firstPoolBorrower].inP2P
                );

                firstPoolBorrower = borrowersOnPool[_poolTokenAddress].getHead();
            }
        }
    }

    /// @notice Unmatches borrowers' liquidity in P2P for the given `_amount` and moves it to Compound.
    /// @dev Note: This function expects and peer-to-peer indexes to have been updated.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function _unmatchBorrowers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        UnmatchVars memory vars;
        vars.poolIndex = ICToken(_poolTokenAddress).borrowIndex();
        vars.p2pIndex = p2pBorrowIndex[_poolTokenAddress];
        address firstP2PBorrower = borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                firstP2PBorrower != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower]
                .inP2P
                .mul(vars.p2pIndex);
                unchecked {
                    vars.toUnmatch = vars.inUnderlying < remainingToUnmatch
                        ? vars.inUnderlying
                        : remainingToUnmatch; // In underlying
                    remainingToUnmatch -= vars.toUnmatch;
                }

                borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].onPool += vars.toUnmatch.div(
                    vars.poolIndex
                ); // In cdUnit.
                borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].inP2P -= vars.toUnmatch.div(
                    vars.p2pIndex
                ); // In peer-to-peer unit.
                _updateBorrowers(_poolTokenAddress, firstP2PBorrower);
                emit BorrowerPositionUpdated(
                    firstP2PBorrower,
                    _poolTokenAddress,
                    borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].onPool,
                    borrowBalanceInOf[_poolTokenAddress][firstP2PBorrower].inP2P
                );

                firstP2PBorrower = borrowersInP2P[_poolTokenAddress].getHead();
            }
        }

        return _amount - remainingToUnmatch;
    }

    /// @notice Updates suppliers data structures with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function _updateSuppliers(address _poolTokenAddress, address _user) internal {
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

    /// @notice Updates borrowers data structures with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function _updateBorrowers(address _poolTokenAddress, address _user) internal {
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
