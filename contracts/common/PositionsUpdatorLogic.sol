// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./libraries/DoubleLinkedList.sol";
import "./interfaces/IPositionsUpdator.sol";
import "./PositionsUpdatorStorage.sol";

contract PositionsUpdatorLogic is IPositionsUpdatorLogic, PositionsUpdatorStorage {
    using DoubleLinkedList for DoubleLinkedList.List;

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     *  @param _maxIterations The max of iterations to do.
     */
    function updateBorrowerPositions(
        address _poolTokenAddress,
        address _account,
        uint256 _maxIterations
    ) external override {
        uint256 onPool = positionsManager.borrowBalanceInOf(_poolTokenAddress, _account).onPool;
        uint256 inP2P = positionsManager.borrowBalanceInOf(_poolTokenAddress, _account).inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            borrowersOnPool[_poolTokenAddress].insertSorted(_account, onPool, _maxIterations);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            borrowersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, _maxIterations);
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     *  @param _maxIterations The max of iterations to do.
     */
    function updateSupplierPositions(
        address _poolTokenAddress,
        address _account,
        uint256 _maxIterations
    ) external override {
        uint256 onPool = positionsManager.supplyBalanceInOf(_poolTokenAddress, _account).onPool;
        uint256 inP2P = positionsManager.supplyBalanceInOf(_poolTokenAddress, _account).inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0))
            suppliersOnPool[_poolTokenAddress].insertSorted(_account, onPool, _maxIterations);

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, _maxIterations);
    }

    function getBorrowerAccountOnPool(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return borrowersOnPool[_poolTokenAddress].getHead();
    }

    function getBorrowerAccountInP2P(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return borrowersInP2P[_poolTokenAddress].getHead();
    }

    function getSupplierAccountOnPool(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return suppliersOnPool[_poolTokenAddress].getHead();
    }

    function getSupplierAccountInP2P(address _poolTokenAddress)
        external
        view
        override
        returns (address)
    {
        return suppliersInP2P[_poolTokenAddress].getHead();
    }
}
