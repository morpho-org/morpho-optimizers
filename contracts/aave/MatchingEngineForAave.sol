// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";
import "./interfaces/IMatchingEngineForAave.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";

import "./positions-manager-parts/PositionsManagerForAaveStorage.sol";

/// @title MatchingEngineManager.
/// @notice Smart contract managing the matching engine.
contract MatchingEngineForAave is IMatchingEngineForAave, PositionsManagerForAaveStorage {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /// Structs ///

    // Struct to avoid stack too deep
    struct Vars {
        uint256 p2pRate;
        uint256 normalizer;
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

    /// @notice Emitted when the borrow P2P delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _supplyP2PDelta The supply P2P delta after update.
    event SupplyP2PDeltaUpdated(address indexed _poolTokenAddress, uint256 _supplyP2PDelta);

    /// External ///

    /// @notice Matches suppliers' liquidity waiting on Aave for the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match suppliers.
    /// @param _underlyingToken The underlying token of the market to find liquidity.
    /// @param _amount The token amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchSuppliers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override returns (uint256 matched) {
        Vars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = suppliersOnPool[poolTokenAddress].getHead();
        vars.normalizer = lendingPool.getReserveNormalizedIncome(address(_underlyingToken));
        vars.p2pRate = marketsManager.supplyP2PExchangeRate(poolTokenAddress);
        Delta storage delta = deltas[poolTokenAddress];

        // Match supply P2P delta first
        if (delta.supplyDelta > 0) {
            uint256 toMatch = Math.min(delta.supplyDelta.mulWadByRay(vars.normalizer), _amount);
            matched += toMatch;
            delta.supplyDelta -= toMatch.divWadByRay(vars.normalizer);
            emit SupplyP2PDeltaUpdated(poolTokenAddress, delta.supplyDelta);
        }

        if (_maxGasToConsume != 0) {
            uint256 gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                user != address(0) &&
                gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                uint256 onPoolInUnderlying = supplyBalanceInOf[poolTokenAddress][user]
                .onPool
                .mulWadByRay(vars.normalizer);
                uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matched);
                matched += toMatch;

                supplyBalanceInOf[poolTokenAddress][user].onPool -= toMatch.divWadByRay(
                    vars.normalizer
                );
                supplyBalanceInOf[poolTokenAddress][user].inP2P += toMatch.divWadByRay(
                    vars.p2pRate
                ); // In p2pUnit
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

        delta.supplyP2PAmount += matched.divWadByRay(vars.p2pRate);
        delta.borrowP2PAmount += matched.divWadByRay(
            marketsManager.borrowP2PExchangeRate(poolTokenAddress)
        );

        if (matched > 0) {
            matched = Math.min(matched, _poolToken.balanceOf(address(this)));
            _withdrawERC20FromPool(poolTokenAddress, _underlyingToken, matched); // Revert on error
        }
    }

    /// @notice Unmatches suppliers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function unmatchSuppliers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override {
        Vars memory vars;
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        address user = suppliersInP2P[_poolTokenAddress].getHead();
        vars.normalizer = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        vars.p2pRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
        uint256 remainingToUnmatch = _amount; // In underlying
        Delta storage delta = deltas[_poolTokenAddress];

        // Reduce borrow P2P delta first
        if (delta.borrowP2PDelta > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            uint256 toMatch = Math.min(
                delta.borrowP2PDelta.mulWadByRay(normalizedVariableDebt),
                _amount
            );
            remainingToUnmatch -= toMatch;
            delta.borrowP2PDelta -= toMatch.divWadByRay(normalizedVariableDebt);
            emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
        }

        if (_maxGasToConsume != 0) {
            uint256 gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                user != address(0) &&
                gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                uint256 toUnmatch = Math.min(
                    supplyBalanceInOf[_poolTokenAddress][user].inP2P.mulWadByRay(vars.p2pRate),
                    remainingToUnmatch
                ); // In underlying
                remainingToUnmatch -= toUnmatch;

                supplyBalanceInOf[_poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                    vars.normalizer
                );
                supplyBalanceInOf[_poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
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

        // If P2P supply amount < _amount, the rest stays on the contract (reserve factor)
        uint256 toSupply = Math.min(_amount, delta.supplyP2PAmount.mulWadByRay(vars.p2pRate));

        if (remainingToUnmatch > 0) {
            delta.supplyDelta += remainingToUnmatch.divWadByRay(vars.normalizer);
            emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyDelta);
        }

        delta.supplyP2PAmount -= (_amount - remainingToUnmatch).divWadByRay(vars.p2pRate);
        delta.borrowP2PAmount -= _amount.divWadByRay(
            marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
        );
        if (toSupply > 0) _supplyERC20ToPool(_poolTokenAddress, underlyingToken, toSupply); // Revert on error
    }

    /// @notice Matches borrowers' liquidity waiting on Aave for the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match borrowers.
    /// @param _underlyingToken The underlying token of the market to find liquidity.
    /// @param _amount The amount to search for (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    /// @return matched The amount of liquidity matched (in underlying).
    function matchBorrowers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override returns (uint256 matched) {
        Vars memory vars;
        address poolTokenAddress = address(_poolToken);
        address user = borrowersOnPool[poolTokenAddress].getHead();
        vars.normalizer = lendingPool.getReserveNormalizedVariableDebt(address(_underlyingToken));
        vars.p2pRate = marketsManager.borrowP2PExchangeRate(poolTokenAddress);
        Delta storage delta = deltas[poolTokenAddress];

        // Match borrow P2P delta first
        if (delta.borrowP2PDelta > 0) {
            uint256 toMatch = Math.min(delta.borrowP2PDelta.mulWadByRay(vars.normalizer), _amount);
            matched += toMatch;
            delta.borrowP2PDelta -= toMatch.divWadByRay(vars.normalizer);
            emit BorrowP2PDeltaUpdated(poolTokenAddress, delta.borrowP2PDelta);
        }

        if (_maxGasToConsume != 0) {
            uint256 gasLeftAtTheBeginning = gasleft();
            while (
                matched < _amount &&
                user != address(0) &&
                gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                uint256 onPoolInUnderlying = borrowBalanceInOf[poolTokenAddress][user]
                .onPool
                .mulWadByRay(vars.normalizer);
                uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matched);
                matched += toMatch;

                borrowBalanceInOf[poolTokenAddress][user].onPool -= toMatch.divWadByRay(
                    vars.normalizer
                );
                borrowBalanceInOf[poolTokenAddress][user].inP2P += toMatch.divWadByRay(
                    vars.p2pRate
                );
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

        delta.supplyP2PAmount += matched.divWadByRay(
            marketsManager.supplyP2PExchangeRate(poolTokenAddress)
        );
        delta.borrowP2PAmount += matched.divWadByRay(vars.p2pRate);

        if (matched > 0)
            _repayERC20ToPool(poolTokenAddress, _underlyingToken, matched, vars.normalizer); // Revert on error
    }

    /// @notice Unmatches borrowers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function unmatchBorrowers(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external override {
        Vars memory vars;
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        address user = borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;
        vars.normalizer = lendingPool.getReserveNormalizedVariableDebt(address(underlyingToken));
        vars.p2pRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
        Delta storage delta = deltas[_poolTokenAddress];

        // Reduce supply P2P delta first
        if (delta.supplyDelta > 0) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            uint256 toUnmatch = Math.min(delta.supplyDelta.mulWadByRay(normalizedIncome), _amount);
            remainingToUnmatch -= toUnmatch;
            delta.supplyDelta -= toUnmatch.divWadByRay(normalizedIncome);
            emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyDelta);
        }

        if (_maxGasToConsume != 0) {
            uint256 gasLeftAtTheBeginning = gasleft();
            while (
                remainingToUnmatch > 0 &&
                user != address(0) &&
                gasLeftAtTheBeginning - gasleft() < _maxGasToConsume
            ) {
                uint256 toUnmatch = Math.min(
                    borrowBalanceInOf[_poolTokenAddress][user].inP2P.mulWadByRay(vars.p2pRate),
                    remainingToUnmatch
                ); // In underlying
                remainingToUnmatch -= toUnmatch;

                borrowBalanceInOf[_poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                    vars.normalizer
                );
                borrowBalanceInOf[_poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
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
            delta.borrowP2PDelta += remainingToUnmatch.divWadByRay(vars.normalizer);
            emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
        }

        delta.supplyP2PAmount -= _amount.divWadByRay(
            marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
        );
        delta.borrowP2PAmount -= (_amount - remainingToUnmatch).divWadByRay(vars.p2pRate);

        _borrowERC20FromPool(_poolTokenAddress, underlyingToken, _amount); // Revert on error
    }

    /// Public ///

    /// @notice Updates borrowers matching engine with the new balances of a given user.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _user The address of the user.
    function updateBorrowers(address _poolTokenAddress, address _user) public override {
        uint256 onPool = borrowBalanceInOf[_poolTokenAddress][_user].onPool;
        uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_user);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_user);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_user);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0)) {
            uint256 totalStaked = IScaledBalanceToken(_poolTokenAddress).scaledTotalSupply();
            (, , address variableDebtTokenAddress) = dataProvider.getReserveTokensAddresses(
                IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()
            );
            rewardsManager.updateUserAssetAndAccruedRewards(
                _user,
                variableDebtTokenAddress,
                formerValueOnPool,
                totalStaked
            );
            borrowersOnPool[_poolTokenAddress].insertSorted(_user, onPool, NDS);
        }

        // Check P2P
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

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_user);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0)) {
            uint256 totalStaked = IScaledBalanceToken(_poolTokenAddress).scaledTotalSupply();
            rewardsManager.updateUserAssetAndAccruedRewards(
                _user,
                _poolTokenAddress,
                formerValueOnPool,
                totalStaked
            );
            suppliersOnPool[_poolTokenAddress].insertSorted(_user, onPool, NDS);
        }

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_user);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, NDS);
    }
}
