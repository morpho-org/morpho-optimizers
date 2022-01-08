// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/IDataUpdator.sol";

import "../common/libraries/DoubleLinkedList.sol";

import "./PositionsManagerForAaveStorage.sol";

contract DataUpdator is IDataUpdator, PositionsManagerForAaveStorage {
    using DoubleLinkedList for DoubleLinkedList.List;

    /// @dev Updates borrowers data structure  with the new balances of a given account.
    /// @param _poolTokenAddress The address of the market on which Morpho want to update the borrower lists.
    /// @param _account The address of the borrower to move.
    function updateBorrowerList(address _poolTokenAddress, address _account) external override {
        uint256 onPool = borrowBalanceInOf[_poolTokenAddress][_account].onPool;
        uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][_account].inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            borrowersOnPool[_poolTokenAddress].insertSorted(_account, onPool, NMAX);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            borrowersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, NMAX);
    }

    /// @dev Updates suppliers data structure  with the new balances of a given account.
    /// @param _poolTokenAddress The address of the market on which Morpho want to update the supplier lists.
    /// @param _account The address of the supplier to move.
    function updateSupplierList(address _poolTokenAddress, address _account) external override {
        uint256 onPool = supplyBalanceInOf[_poolTokenAddress][_account].onPool;
        uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][_account].inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            suppliersOnPool[_poolTokenAddress].insertSorted(_account, onPool, NMAX);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, NMAX);
    }
}
