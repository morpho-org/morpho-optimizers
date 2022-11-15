// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {MorphoStorage as S} from "../storage/MorphoStorage.sol";

import {LibIndexes} from "./LibIndexes.sol";
import {LibMarkets} from "./LibMarkets.sol";
import {LibUsers} from "./LibUsers.sol";

import {HeapOrdering, Types, Math, EventsAndErrors as E, WadRayMath} from "./Libraries.sol";
import {IScaledBalanceToken} from "../interfaces/Interfaces.sol";

library LibMatching {
    using HeapOrdering for HeapOrdering.HeapArray;
    using WadRayMath for uint256;

    function g() internal pure returns (S.GlobalLayout storage g) {
        g = S.globalLayout();
    }

    function p() internal pure returns (S.PositionsLayout storage p) {
        p = S.positionsLayout();
    }

    function m() internal pure returns (S.MarketsLayout storage m) {
        m = S.marketsLayout();
    }

    function c() internal pure returns (S.ContractsLayout storage c) {
        c = S.contractsLayout();
    }

    // Struct to avoid stack too deep.
    struct MatchVars {
        address firstPoolSupplier;
        uint256 remainingToMatch;
        uint256 p2pIndex;
        uint256 toMatch;
        uint256 poolIndex;
        uint256 gasLeftAtTheBeginning;
    }

    function matchSuppliers(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) internal returns (uint256 matched, uint256 gasConsumedInMatching) {
        if (_maxGasForMatching == 0) return (0, 0);

        MatchVars memory vars;
        vars.poolIndex = m().poolIndexes[_poolToken].poolSupplyIndex;
        vars.p2pIndex = m().p2pSupplyIndex[_poolToken];
        vars.remainingToMatch = _amount;
        vars.gasLeftAtTheBeginning = gasleft();

        while (
            vars.remainingToMatch > 0 &&
            (vars.firstPoolSupplier = p().suppliersOnPool[_poolToken].getHead()) != address(0)
        ) {
            // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
            unchecked {
                if (vars.gasLeftAtTheBeginning - gasleft() >= _maxGasForMatching) break;
            }
            Types.Balance storage firstPoolSupplierBalance = p().supplyBalanceInOf[_poolToken][
                vars.firstPoolSupplier
            ];
            vars = matchSupplierSingle(vars, firstPoolSupplierBalance);
            updateSupplierInDS(_poolToken, vars.firstPoolSupplier);
            // emit E.SupplierPositionUpdated(
            //     vars.firstPoolSupplier,
            //     _poolToken,
            //     firstPoolSupplierBalance.inP2P,
            //     firstPoolSupplierBalance.onPool
            // );
        }

        // Safe unchecked because `gasLeftAtTheBeginning` >= gas left now.
        // And _amount >= remainingToMatch.
        unchecked {
            matched = _amount - vars.remainingToMatch;
            gasConsumedInMatching = vars.gasLeftAtTheBeginning - gasleft();
        }
    }

    function matchSupplierSingle(MatchVars memory vars, Types.Balance storage firstSupplierBalance)
        internal
        returns (MatchVars memory)
    {
        uint256 poolSupplyBalance = firstSupplierBalance.onPool;
        uint256 p2pSupplyBalance = firstSupplierBalance.inP2P;

        vars.toMatch = Math.min(poolSupplyBalance.rayMul(vars.poolIndex), vars.remainingToMatch);
        vars.remainingToMatch -= vars.toMatch;

        poolSupplyBalance -= vars.toMatch.rayDiv(vars.poolIndex);
        p2pSupplyBalance += vars.toMatch.rayDiv(vars.p2pIndex);

        firstSupplierBalance.onPool = poolSupplyBalance;
        firstSupplierBalance.inP2P = p2pSupplyBalance;
        return vars;
    }

    /// @notice Updates `_user` positions in the supplier data structures.
    /// @param _poolToken The address of the market on which to update the suppliers data structure.
    /// @param _user The address of the user.
    function updateSupplierInDS(address _poolToken, address _user) internal {
        Types.Balance storage supplierSupplyBalance = p().supplyBalanceInOf[_poolToken][_user];
        uint256 onPool = supplierSupplyBalance.onPool;
        uint256 inP2P = supplierSupplyBalance.inP2P;
        HeapOrdering.HeapArray storage marketSuppliersOnPool = p().suppliersOnPool[_poolToken];
        HeapOrdering.HeapArray storage marketSuppliersInP2P = p().suppliersInP2P[_poolToken];

        uint256 formerValueOnPool = marketSuppliersOnPool.getValueOf(_user);
        uint256 formerValueInP2P = marketSuppliersInP2P.getValueOf(_user);

        marketSuppliersOnPool.update(_user, formerValueOnPool, onPool, g().maxSortedUsers);
        marketSuppliersInP2P.update(_user, formerValueInP2P, inP2P, g().maxSortedUsers);

        if (formerValueOnPool != onPool && address(c().rewardsManager) != address(0))
            c().rewardsManager.updateUserAssetAndAccruedRewards(
                c().rewardsController,
                _user,
                _poolToken,
                formerValueOnPool,
                IScaledBalanceToken(_poolToken).scaledTotalSupply()
            );
    }

    function updateBorrowerInDS(address _poolToken, address _user) internal {
        Types.Balance storage borrowerBorrowBalance = p().borrowBalanceInOf[_poolToken][_user];
        uint256 onPool = borrowerBorrowBalance.onPool;
        uint256 inP2P = borrowerBorrowBalance.inP2P;
        HeapOrdering.HeapArray storage marketBorrowersOnPool = p().borrowersOnPool[_poolToken];
        HeapOrdering.HeapArray storage marketBorrowersInP2P = p().borrowersInP2P[_poolToken];

        uint256 formerValueOnPool = marketBorrowersOnPool.getValueOf(_user);
        uint256 formerValueInP2P = marketBorrowersInP2P.getValueOf(_user);

        marketBorrowersOnPool.update(_user, formerValueOnPool, onPool, g().maxSortedUsers);
        marketBorrowersInP2P.update(_user, formerValueInP2P, inP2P, g().maxSortedUsers);

        if (formerValueOnPool != onPool && address(c().rewardsManager) != address(0)) {
            address variableDebtTokenAddress = c()
            .pool
            .getReserveData(m().market[_poolToken].underlyingToken)
            .variableDebtTokenAddress;
            c().rewardsManager.updateUserAssetAndAccruedRewards(
                c().rewardsController,
                _user,
                variableDebtTokenAddress,
                formerValueOnPool,
                IScaledBalanceToken(variableDebtTokenAddress).scaledTotalSupply()
            );
        }
    }
}
