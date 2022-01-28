// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";
import "./interfaces/IMatchingEngineForAave.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/aave/WadRayMath.sol";

import "../common/libraries/DoubleLinkedList.sol";

import "./PositionsManagerForAaveStorage.sol";

/// @title MatchingEngineManager
/// @notice Smart contract managing the matching engine.
contract MatchingEngineForAave is IMatchingEngineForAave, PositionsManagerForAaveStorage {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

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
    /// @return matchedSupply The amount of liquidity matched (in underlying).
    function matchSuppliers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) external override returns (uint256 matchedSupply) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        address user = suppliersOnPool[poolTokenAddress].getHead();
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(poolTokenAddress);
        uint256 iterationCount;

        // Match supply P2P delta first
        if (supplyP2PDelta[poolTokenAddress] > 0) {
            uint256 toMatch = Math.min(
                supplyP2PDelta[poolTokenAddress].mulWadByRay(normalizedIncome),
                _amount
            );
            matchedSupply += toMatch;
            supplyP2PDelta[poolTokenAddress] -= toMatch.divWadByRay(normalizedIncome);
            emit SupplyP2PDeltaUpdated(poolTokenAddress, supplyP2PDelta[poolTokenAddress]);
        }

        while (matchedSupply < _amount && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = supplyBalanceInOf[poolTokenAddress][user]
            .onPool
            .mulWadByRay(normalizedIncome);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedSupply);
            matchedSupply += toMatch;
            supplyBalanceInOf[poolTokenAddress][user].onPool -= toMatch.divWadByRay(
                normalizedIncome
            );
            supplyBalanceInOf[poolTokenAddress][user].inP2P += toMatch.divWadByRay(
                supplyP2PExchangeRate
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

        supplyP2PAmount[poolTokenAddress] += matchedSupply.divWadByRay(supplyP2PExchangeRate);
        borrowP2PAmount[poolTokenAddress] += matchedSupply.divWadByRay(
            marketsManager.borrowP2PExchangeRate(poolTokenAddress)
        );

        if (matchedSupply > 0) {
            matchedSupply = Math.min(matchedSupply, _poolToken.balanceOf(address(this)));
            _withdrawERC20FromPool(poolTokenAddress, _underlyingToken, matchedSupply); // Revert on error
        }
    }

    /// @notice Unmatches suppliers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    function unmatchSuppliers(address _poolTokenAddress, uint256 _amount) public override {
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(address(underlyingToken));
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(_poolTokenAddress);
        address user = suppliersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount; // In underlying
        uint256 iterationCount;

        // Reduce borrow P2P delta first
        if (borrowP2PDelta[_poolTokenAddress] > 0) {
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
                address(underlyingToken)
            );
            uint256 toMatch = Math.min(
                borrowP2PDelta[_poolTokenAddress].mulWadByRay(normalizedVariableDebt),
                _amount
            );
            remainingToUnmatch -= toMatch;
            borrowP2PDelta[_poolTokenAddress] -= toMatch.divWadByRay(normalizedVariableDebt);
            emit BorrowP2PDeltaUpdated(_poolTokenAddress, borrowP2PDelta[_poolTokenAddress]);
        }

        while (remainingToUnmatch > 0 && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][user].inP2P; // In poolToken
            uint256 toUnmatch = Math.min(
                inP2P.mulWadByRay(supplyP2PExchangeRate),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;
            supplyBalanceInOf[_poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                normalizedIncome
            );
            supplyBalanceInOf[_poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
                supplyP2PExchangeRate
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

        // If P2PAmount < _amount, the rest stays on the contract (reserve factor)
        uint256 toSupply = Math.min(
            _amount,
            supplyP2PAmount[_poolTokenAddress].mulWadByRay(supplyP2PExchangeRate)
        );

        if (remainingToUnmatch > 0) {
            supplyP2PDelta[_poolTokenAddress] += remainingToUnmatch.divWadByRay(normalizedIncome);
            emit SupplyP2PDeltaUpdated(_poolTokenAddress, supplyP2PDelta[_poolTokenAddress]);
        }

        supplyP2PAmount[_poolTokenAddress] -= (_amount - remainingToUnmatch).divWadByRay(
            supplyP2PExchangeRate
        );
        borrowP2PAmount[_poolTokenAddress] -= _amount.divWadByRay(
            marketsManager.borrowP2PExchangeRate(_poolTokenAddress)
        );

        if (toSupply > 0) _supplyERC20ToPool(_poolTokenAddress, underlyingToken, toSupply); // Revert on error
    }

    /// @notice Matches borrowers' liquidity waiting on Aave for the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match borrowers.
    /// @param _underlyingToken The underlying token of the market to find liquidity.
    /// @param _amount The amount to search for (in underlying).
    /// @return matchedBorrow The amount of liquidity matched (in underlying).
    function matchBorrowers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) external override returns (uint256 matchedBorrow) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(_underlyingToken)
        );
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(poolTokenAddress);
        address user = borrowersOnPool[poolTokenAddress].getHead();
        uint256 iterationCount;

        // Match borrow P2P delta first
        if (borrowP2PDelta[poolTokenAddress] > 0) {
            uint256 toMatch = Math.min(
                borrowP2PDelta[poolTokenAddress].mulWadByRay(normalizedVariableDebt),
                _amount
            );
            matchedBorrow += toMatch;
            borrowP2PDelta[poolTokenAddress] -= toMatch.divWadByRay(normalizedVariableDebt);
            emit BorrowP2PDeltaUpdated(poolTokenAddress, borrowP2PDelta[poolTokenAddress]);
        }

        while (matchedBorrow < _amount && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = borrowBalanceInOf[poolTokenAddress][user]
            .onPool
            .mulWadByRay(normalizedVariableDebt);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedBorrow);
            matchedBorrow += toMatch;
            borrowBalanceInOf[poolTokenAddress][user].onPool -= toMatch.divWadByRay(
                normalizedVariableDebt
            );
            borrowBalanceInOf[poolTokenAddress][user].inP2P += toMatch.divWadByRay(
                borrowP2PExchangeRate
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

        supplyP2PAmount[poolTokenAddress] += matchedBorrow.divWadByRay(
            marketsManager.supplyP2PExchangeRate(poolTokenAddress)
        );
        borrowP2PAmount[poolTokenAddress] += matchedBorrow.divWadByRay(borrowP2PExchangeRate);

        if (matchedBorrow > 0)
            _repayERC20ToPool(
                poolTokenAddress,
                _underlyingToken,
                matchedBorrow,
                normalizedVariableDebt
            ); // Revert on error
    }

    /// @notice Unmatches borrowers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    function unmatchBorrowers(address _poolTokenAddress, uint256 _amount) public override {
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(_poolTokenAddress);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            address(underlyingToken)
        );
        address user = borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;
        uint256 iterationCount;

        // Reduce supply P2P delta first
        if (supplyP2PDelta[_poolTokenAddress] > 0) {
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(
                address(underlyingToken)
            );
            uint256 toMatch = Math.min(
                supplyP2PDelta[_poolTokenAddress].mulWadByRay(normalizedIncome),
                _amount
            );
            remainingToUnmatch -= toMatch;
            supplyP2PDelta[_poolTokenAddress] -= toMatch.divWadByRay(normalizedIncome);
            emit SupplyP2PDeltaUpdated(_poolTokenAddress, supplyP2PDelta[_poolTokenAddress]);
        }

        while (remainingToUnmatch > 0 && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][user].inP2P;
            uint256 toUnmatch = Math.min(
                inP2P.mulWadByRay(borrowP2PExchangeRate),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;
            borrowBalanceInOf[_poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                normalizedVariableDebt
            );
            borrowBalanceInOf[_poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
                borrowP2PExchangeRate
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

        if (remainingToUnmatch > 0) {
            borrowP2PDelta[_poolTokenAddress] += remainingToUnmatch.divWadByRay(
                normalizedVariableDebt
            );
            emit BorrowP2PDeltaUpdated(_poolTokenAddress, borrowP2PDelta[_poolTokenAddress]);
        }

        supplyP2PAmount[_poolTokenAddress] -= _amount.divWadByRay(
            marketsManager.supplyP2PExchangeRate(_poolTokenAddress)
        );
        borrowP2PAmount[_poolTokenAddress] -= (_amount - remainingToUnmatch).divWadByRay(
            borrowP2PExchangeRate
        );

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
            borrowersOnPool[_poolTokenAddress].insertSorted(_user, onPool, NMAX);
        }

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_user);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            borrowersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, NMAX);
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
            suppliersOnPool[_poolTokenAddress].insertSorted(_user, onPool, NMAX);
        }

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_user);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_user, inP2P, NMAX);
    }
}
