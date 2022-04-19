// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";

import {LibStorage, MarketsStorage, PositionsStorage} from "./LibStorage.sol";
import "../../common/libraries/DoubleLinkedList.sol";
import "./CompoundMath.sol";

library LibMatchingEngine {
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

    /// STORAGE GETTERS ///

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }

    /// INTERNAL ///

    /// @dev Matches suppliers' liquidity waiting on Compound up to the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchSuppliers(
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256 matched) {
        PositionsStorage storage p = ps();
        MatchVars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = p.suppliersOnPool[poolTokenAddress].getHead();
        vars.poolIndex = _poolToken.exchangeRateCurrent();
        vars.p2pRate = ms().supplyP2PExchangeRate[poolTokenAddress];

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                uint256 onPool = p.supplyBalanceInOf[poolTokenAddress][user].onPool;
                vars.inUnderlying = onPool.mul(vars.poolIndex);
                unchecked {
                    vars.toMatch = vars.inUnderlying < _amount - matched
                        ? vars.inUnderlying
                        : _amount - matched;
                    matched += vars.toMatch;
                }

                // Handle rounding error of 1 wei.
                uint256 diff = p.supplyBalanceInOf[poolTokenAddress][user].onPool -
                    vars.toMatch.div(vars.poolIndex);
                p.supplyBalanceInOf[poolTokenAddress][user].onPool = diff == 1 ? 0 : diff;
                p.supplyBalanceInOf[poolTokenAddress][user].inP2P += vars.toMatch.div(vars.p2pRate); // In p2pUnit
                updateSuppliers(poolTokenAddress, user);
                emit SupplierPositionUpdated(
                    user,
                    poolTokenAddress,
                    p.supplyBalanceInOf[poolTokenAddress][user].onPool,
                    p.supplyBalanceInOf[poolTokenAddress][user].inP2P
                );

                user = p.suppliersOnPool[poolTokenAddress].getHead();
            }
        }
    }

    /// @dev Unmatches suppliers' liquidity in P2P up to the given `_amount` and move it to Compound.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function unmatchSuppliers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        PositionsStorage storage p = ps();
        UnmatchVars memory vars;
        address user = p.suppliersInP2P[_poolTokenAddress].getHead();
        vars.poolIndex = ICToken(_poolTokenAddress).exchangeRateCurrent();
        vars.p2pRate = ms().supplyP2PExchangeRate[_poolTokenAddress];
        uint256 remainingToUnmatch = _amount; // In underlying

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = p.supplyBalanceInOf[_poolTokenAddress][user].inP2P.mul(
                    vars.p2pRate
                );
                unchecked {
                    vars.toUnmatch = vars.inUnderlying < remainingToUnmatch
                        ? vars.inUnderlying
                        : remainingToUnmatch; // In underlying
                    remainingToUnmatch -= vars.toUnmatch;
                }

                p.supplyBalanceInOf[_poolTokenAddress][user].onPool += vars.toUnmatch.div(
                    vars.poolIndex
                );
                // Handle rounding error of 1 wei.
                uint256 diff = p.supplyBalanceInOf[_poolTokenAddress][user].inP2P -
                    vars.toUnmatch.div(vars.p2pRate);
                p.supplyBalanceInOf[_poolTokenAddress][user].inP2P = diff == 1 ? 0 : diff; // In p2pUnit
                updateSuppliers(_poolTokenAddress, user);
                emit SupplierPositionUpdated(
                    user,
                    _poolTokenAddress,
                    p.supplyBalanceInOf[_poolTokenAddress][user].onPool,
                    p.supplyBalanceInOf[_poolTokenAddress][user].inP2P
                );

                user = p.suppliersInP2P[_poolTokenAddress].getHead();
            }
        }

        return _amount - remainingToUnmatch;
    }

    /// @dev Matches borrowers' liquidity waiting on Compound up to the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchBorrowers(
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256 matched) {
        PositionsStorage storage p = ps();
        MatchVars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = p.borrowersOnPool[poolTokenAddress].getHead();
        vars.poolIndex = _poolToken.borrowIndex();
        vars.p2pRate = ms().borrowP2PExchangeRate[poolTokenAddress];

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = p.borrowBalanceInOf[poolTokenAddress][user].onPool.mul(
                    vars.poolIndex
                );
                unchecked {
                    vars.toMatch = vars.inUnderlying < _amount - matched
                        ? vars.inUnderlying
                        : _amount - matched;
                    matched += vars.toMatch;
                }

                // Handle rounding error of 1 wei.
                uint256 diff = p.borrowBalanceInOf[poolTokenAddress][user].onPool -
                    vars.toMatch.div(vars.poolIndex);
                p.borrowBalanceInOf[poolTokenAddress][user].onPool = diff == 1 ? 0 : diff;
                p.borrowBalanceInOf[poolTokenAddress][user].inP2P += vars.toMatch.div(vars.p2pRate);
                updateBorrowers(poolTokenAddress, user);
                emit BorrowerPositionUpdated(
                    user,
                    poolTokenAddress,
                    p.borrowBalanceInOf[poolTokenAddress][user].onPool,
                    p.borrowBalanceInOf[poolTokenAddress][user].inP2P
                );

                user = p.borrowersOnPool[poolTokenAddress].getHead();
            }
        }
    }

    /// @dev Unmatches borrowers' liquidity in P2P for the given `_amount` and move it to Compound.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return The amount unmatched (in underlying).
    function unmatchBorrowers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) internal returns (uint256) {
        PositionsStorage storage p = ps();
        UnmatchVars memory vars;
        address user = p.borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;
        vars.poolIndex = ICToken(_poolTokenAddress).borrowIndex();
        vars.p2pRate = ms().borrowP2PExchangeRate[_poolTokenAddress];

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = p.borrowBalanceInOf[_poolTokenAddress][user].inP2P.mul(
                    vars.p2pRate
                );
                unchecked {
                    vars.toUnmatch = vars.inUnderlying < remainingToUnmatch
                        ? vars.inUnderlying
                        : remainingToUnmatch; // In underlying
                    remainingToUnmatch -= vars.toUnmatch;
                }

                p.borrowBalanceInOf[_poolTokenAddress][user].onPool += vars.toUnmatch.div(
                    vars.poolIndex
                );
                p.borrowBalanceInOf[_poolTokenAddress][user].inP2P -= vars.toUnmatch.div(
                    vars.p2pRate
                );
                updateBorrowers(_poolTokenAddress, user);
                emit BorrowerPositionUpdated(
                    user,
                    _poolTokenAddress,
                    p.borrowBalanceInOf[_poolTokenAddress][user].onPool,
                    p.borrowBalanceInOf[_poolTokenAddress][user].inP2P
                );

                user = p.borrowersInP2P[_poolTokenAddress].getHead();
            }
        }

        return _amount - remainingToUnmatch;
    }

    /// PUBLIC ///

    /// @dev Updates borrowers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function updateBorrowers(address _poolTokenAddress, address _user) internal {
        PositionsStorage storage p = ps();
        uint256 onPool = p.borrowBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = p.borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = p.borrowersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = p.borrowersInP2P[_poolTokenAddress].getValueOf(_user);

        // Check pool.
        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) p.borrowersOnPool[_poolTokenAddress].remove(_user);
            if (onPool > 0) p.borrowersOnPool[_poolTokenAddress].insertSorted(_user, onPool, p.NDS);
        }

        // Check P2P.
        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) p.borrowersInP2P[_poolTokenAddress].remove(_user);
            if (inP2P > 0) p.borrowersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, p.NDS);
        }

        if (p.isCompRewardsActive && address(p.rewardsManager) != address(0))
            p.rewardsManager.accrueUserBorrowUnclaimedRewards(
                _user,
                _poolTokenAddress,
                formerValueOnPool
            );
    }

    /// @dev Updates suppliers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function updateSuppliers(address _poolTokenAddress, address _user) internal {
        PositionsStorage storage p = ps();
        uint256 onPool = p.supplyBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = p.supplyBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = p.suppliersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = p.suppliersInP2P[_poolTokenAddress].getValueOf(_user);

        // Check pool.
        if (formerValueOnPool != onPool) {
            if (formerValueOnPool > 0) p.suppliersOnPool[_poolTokenAddress].remove(_user);
            if (onPool > 0) p.suppliersOnPool[_poolTokenAddress].insertSorted(_user, onPool, p.NDS);
        }

        // Check P2P.
        if (formerValueInP2P != inP2P) {
            if (formerValueInP2P > 0) p.suppliersInP2P[_poolTokenAddress].remove(_user);
            if (inP2P > 0) p.suppliersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, p.NDS);
        }

        if (p.isCompRewardsActive && address(p.rewardsManager) != address(0))
            p.rewardsManager.accrueUserSupplyUnclaimedRewards(
                _user,
                _poolTokenAddress,
                formerValueOnPool
            );
    }
}
