// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./positions-manager-parts/PositionsManagerForCompoundStorage.sol";

/// @title MatchingEngineManager.
/// @notice Smart contract managing the matching engine.
contract MatchingEngineForCompound is
    IMatchingEngineForCompound,
    PositionsManagerForCompoundStorage
{
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

    /// @notice Emitted when the borrow P2P delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _borrowP2PDelta The borrow P2P delta after update.
    event BorrowP2PDeltaUpdated(address indexed _poolTokenAddress, uint256 _borrowP2PDelta);

    /// @notice Emitted when the supply P2P delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _supplyP2PDelta The supply P2P delta after update.
    event SupplyP2PDeltaUpdated(address indexed _poolTokenAddress, uint256 _supplyP2PDelta);

    /// @notice Emitted when the supply and borrow P2P amounts are updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _supplyP2PAmount The supply P2P amount after update.
    /// @param _borrowP2PAmount The borrow P2P amount after update.
    event P2PAmountsUpdated(
        address indexed _poolTokenAddress,
        uint256 _supplyP2PAmount,
        uint256 _borrowP2PAmount
    );

    /// EXTERNAL ///

    /// @notice Matches suppliers' liquidity waiting on Compound up to the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match suppliers.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchSuppliers(
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override returns (uint256 matched) {
        MatchVars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = suppliersOnPool[poolTokenAddress].getHead();
        vars.poolIndex = _poolToken.exchangeRateCurrent();
        vars.p2pRate = marketsManager.supplyP2PExchangeRate(poolTokenAddress);
        Delta storage delta = deltas[poolTokenAddress];

        // Match supply P2P delta first
        if (delta.supplyP2PDelta > 0) {
            vars.toMatch = Math.min(delta.supplyP2PDelta.mul(vars.poolIndex), _amount);
            matched += vars.toMatch;
            delta.supplyP2PDelta -= vars.toMatch.div(vars.poolIndex);
            emit SupplyP2PDeltaUpdated(poolTokenAddress, delta.supplyP2PDelta);
        }

        if (_maxGasToConsume != 0) {
            vars.gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                user != address(0) &&
                vars.gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                vars.inUnderlying = supplyBalanceInOf[poolTokenAddress][user].onPool.mul(
                    vars.poolIndex
                );
                unchecked {
                    vars.toMatch = vars.inUnderlying < _amount - matched
                        ? vars.inUnderlying
                        : _amount - matched;
                    matched += vars.toMatch;
                }

                supplyBalanceInOf[poolTokenAddress][user].onPool -= vars.toMatch.div(
                    vars.poolIndex
                );
                supplyBalanceInOf[poolTokenAddress][user].inP2P += vars.toMatch.div(vars.p2pRate); // In p2pUnit
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

        delta.supplyP2PAmount += matched.div(vars.p2pRate);
        delta.borrowP2PAmount += matched.div(
            marketsManager.borrowP2PExchangeRate(poolTokenAddress)
        );
        emit P2PAmountsUpdated(poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
    }

    /// @notice Unmatches suppliers' liquidity in P2P up to the given `_amount` and move it to Compound.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function unmatchSuppliers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override returns (uint256 toSupply) {
        UnmatchVars memory vars;
        address user = suppliersInP2P[_poolTokenAddress].getHead();
        vars.poolIndex = ICToken(_poolTokenAddress).exchangeRateCurrent();
        vars.p2pRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
        uint256 remainingToUnmatch = _amount; // In underlying
        Delta storage delta = deltas[_poolTokenAddress];

        // Reduce borrow P2P delta first
        if (delta.borrowP2PDelta > 0) {
            uint256 borrowPoolIndex = ICToken(_poolTokenAddress).borrowIndex();
            vars.toUnmatch = Math.min(delta.borrowP2PDelta.mul(borrowPoolIndex), _amount);
            remainingToUnmatch -= vars.toUnmatch;
            delta.borrowP2PDelta -= vars.toUnmatch.div(borrowPoolIndex);
            emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
        }

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
                ); // In p2pUnit
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

        // If P2P supply amount < _amount, the rest stays on the contract (reserve factor).
        toSupply = Math.min(_amount, delta.supplyP2PAmount.mul(vars.p2pRate));

        if (remainingToUnmatch > 0) {
            delta.supplyP2PDelta += remainingToUnmatch.div(vars.poolIndex);
            emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
        }

        delta.supplyP2PAmount -= (_amount - remainingToUnmatch).div(vars.p2pRate);
        delta.borrowP2PAmount -= _amount.div(
            marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
        );
        emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
    }

    /// @notice Matches borrowers' liquidity waiting on Compound up to the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match borrowers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchBorrowers(
        ICToken _poolToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override returns (uint256 matched) {
        MatchVars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = borrowersOnPool[poolTokenAddress].getHead();
        vars.poolIndex = _poolToken.borrowIndex();
        vars.p2pRate = marketsManager.borrowP2PExchangeRate(poolTokenAddress);
        Delta storage delta = deltas[poolTokenAddress];

        // Match borrow P2P delta first
        if (delta.borrowP2PDelta > 0) {
            vars.toMatch = Math.min(delta.borrowP2PDelta.mul(vars.poolIndex), _amount);
            matched += vars.toMatch;
            delta.borrowP2PDelta -= vars.toMatch.div(vars.poolIndex);
            emit BorrowP2PDeltaUpdated(poolTokenAddress, delta.borrowP2PDelta);
        }

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

        delta.supplyP2PAmount += matched.div(
            marketsManager.supplyP2PExchangeRate(poolTokenAddress)
        );
        delta.borrowP2PAmount += matched.div(vars.p2pRate);
        emit P2PAmountsUpdated(poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
    }

    /// @notice Unmatches borrowers' liquidity in P2P for the given `_amount` and move it to Compound.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function unmatchBorrowers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override {
        UnmatchVars memory vars;
        address user = borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;
        vars.poolIndex = ICToken(_poolTokenAddress).borrowIndex();
        vars.p2pRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
        Delta storage delta = deltas[_poolTokenAddress];

        // Reduce supply P2P delta first.
        if (delta.supplyP2PDelta > 0) {
            uint256 supplyPoolIndex = ICToken(_poolTokenAddress).exchangeRateCurrent();
            vars.toUnmatch = Math.min(delta.supplyP2PDelta.mul(supplyPoolIndex), _amount);
            remainingToUnmatch -= vars.toUnmatch;
            delta.supplyP2PDelta -= vars.toUnmatch.div(supplyPoolIndex);
            emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
        }

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

        if (remainingToUnmatch > 0) {
            delta.borrowP2PDelta += remainingToUnmatch.div(vars.poolIndex);
            emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
        }

        delta.supplyP2PAmount -= _amount.div(
            marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
        );
        delta.borrowP2PAmount -= (_amount - remainingToUnmatch).div(vars.p2pRate);
        emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
    }

    /// PUBLIC ///

    /// @notice Updates borrowers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function updateBorrowers(address _poolTokenAddress, address _user) public override {
        uint256 onPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_user);

        // Check pool.
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_user);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            borrowersOnPool[_poolTokenAddress].insertSorted(_user, onPool, NDS);

        // Check P2P.
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_user);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            borrowersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, NDS);
    }

    /// @notice Updates suppliers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function updateSuppliers(address _poolTokenAddress, address _user) public override {
        uint256 onPool = supplyBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_user);

        // Check pool.
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_user);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            suppliersOnPool[_poolTokenAddress].insertSorted(_user, onPool, NDS);

        // Check P2P.
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_user);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, NDS);
    }
}
