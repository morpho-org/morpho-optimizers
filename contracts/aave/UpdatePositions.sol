// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./PositionsManagerStorageForAave.sol";

/**
 *  @title UpdatePositions.
 *  @dev Allows to move the logic from the positions manager to this contract.
 */
contract UpdatePositions is ReentrancyGuard, PositionsManagerStorageForAave {
    using RedBlackBinaryTree for RedBlackBinaryTree.Tree;
    using EnumerableSet for EnumerableSet.AddressSet;

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function updateBorrowerList(address _poolTokenAddress, address _account) external {
        uint256 onPool = borrowBalanceInOf[_poolTokenAddress][_account].onPool;
        uint256 inP2P = borrowBalanceInOf[_poolTokenAddress][_account].inP2P;
        uint256 numberOfBorrowersOnPool = borrowersOnPool[_poolTokenAddress].numberOfKeys();
        uint256 numberOfBorrowersInP2P = borrowersInP2P[_poolTokenAddress].numberOfKeys();
        bool isOnPool = borrowersOnPool[_poolTokenAddress].keyExists(_account);
        bool isInP2P = borrowersInP2P[_poolTokenAddress].keyExists(_account);

        // Check pool
        bool isOnPoolAndValueChanged = isOnPool &&
            borrowersOnPool[_poolTokenAddress].getValueOfKey(_account) != onPool;
        if (isOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (isOnPoolAndValueChanged || !isOnPool)) {
            if (numberOfBorrowersOnPool <= NMAX) {
                numberOfBorrowersOnPool++;
                borrowersOnPool[_poolTokenAddress].insert(_account, onPool);
            } else {
                (uint256 minimum, address minimumAccount) = borrowersOnPool[_poolTokenAddress]
                    .getMinimum();
                if (onPool > minimum) {
                    borrowersOnPool[_poolTokenAddress].remove(minimumAccount);
                    borrowersOnPoolBuffer[_poolTokenAddress].add(minimumAccount);
                    borrowersOnPool[_poolTokenAddress].insert(_account, onPool);
                } else borrowersOnPoolBuffer[_poolTokenAddress].add(_account);
            }
        }
        if (onPool == 0 && borrowersOnPoolBuffer[_poolTokenAddress].contains(_account))
            borrowersOnPoolBuffer[_poolTokenAddress].remove(_account);

        // Check P2P
        bool isInP2PAndValueChanged = isInP2P &&
            borrowersInP2P[_poolTokenAddress].getValueOfKey(_account) != inP2P;
        if (isInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (isInP2PAndValueChanged || !isInP2P)) {
            if (numberOfBorrowersInP2P <= NMAX) {
                numberOfBorrowersInP2P++;
                borrowersInP2P[_poolTokenAddress].insert(_account, inP2P);
            } else {
                (uint256 minimum, address minimumAccount) = borrowersInP2P[_poolTokenAddress]
                    .getMinimum();
                if (inP2P > minimum) {
                    borrowersInP2P[_poolTokenAddress].remove(minimumAccount);
                    borrowersInP2PBuffer[_poolTokenAddress].add(minimumAccount);
                    borrowersInP2P[_poolTokenAddress].insert(_account, inP2P);
                } else borrowersInP2PBuffer[_poolTokenAddress].add(_account);
            }
        }
        if (inP2P == 0 && borrowersInP2PBuffer[_poolTokenAddress].contains(_account))
            borrowersInP2PBuffer[_poolTokenAddress].remove(_account);

        // Add user to the trees if possible
        if (
            borrowersOnPoolBuffer[_poolTokenAddress].length() > 0 && numberOfBorrowersOnPool <= NMAX
        ) {
            address account = borrowersOnPoolBuffer[_poolTokenAddress].at(0);
            uint256 value = borrowBalanceInOf[_poolTokenAddress][account].onPool;
            borrowersOnPoolBuffer[_poolTokenAddress].remove(account);
            borrowersOnPool[_poolTokenAddress].insert(account, value);
        }
        if (
            borrowersInP2PBuffer[_poolTokenAddress].length() > 0 && numberOfBorrowersInP2P <= NMAX
        ) {
            address account = borrowersInP2PBuffer[_poolTokenAddress].at(0);
            uint256 value = borrowBalanceInOf[_poolTokenAddress][account].inP2P;
            borrowersInP2PBuffer[_poolTokenAddress].remove(account);
            borrowersInP2P[_poolTokenAddress].insert(account, value);
        }
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _poolTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function updateSupplierList(address _poolTokenAddress, address _account) external {
        uint256 onPool = supplyBalanceInOf[_poolTokenAddress][_account].onPool;
        uint256 inP2P = supplyBalanceInOf[_poolTokenAddress][_account].inP2P;
        uint256 numberOfSuppliersOnPool = suppliersOnPool[_poolTokenAddress].numberOfKeys();
        uint256 numberOfSuppliersInP2P = suppliersInP2P[_poolTokenAddress].numberOfKeys();
        bool isOnPool = suppliersOnPool[_poolTokenAddress].keyExists(_account);
        bool isInP2P = suppliersInP2P[_poolTokenAddress].keyExists(_account);

        // Check pool
        bool isOnPoolAndValueChanged = isOnPool &&
            suppliersOnPool[_poolTokenAddress].getValueOfKey(_account) != onPool;
        if (isOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (isOnPoolAndValueChanged || !isOnPool)) {
            if (numberOfSuppliersOnPool <= NMAX) {
                numberOfSuppliersOnPool++;
                suppliersOnPool[_poolTokenAddress].insert(_account, onPool);
            } else {
                (uint256 minimum, address minimumAccount) = suppliersOnPool[_poolTokenAddress]
                    .getMinimum();
                if (onPool > minimum) {
                    suppliersOnPool[_poolTokenAddress].remove(minimumAccount);
                    suppliersOnPoolBuffer[_poolTokenAddress].add(minimumAccount);
                    suppliersOnPool[_poolTokenAddress].insert(_account, onPool);
                } else suppliersOnPoolBuffer[_poolTokenAddress].add(_account);
            }
        }
        if (onPool == 0 && suppliersOnPoolBuffer[_poolTokenAddress].contains(_account))
            suppliersOnPoolBuffer[_poolTokenAddress].remove(_account);

        // Check P2P
        bool isInP2PAndValueChanged = isInP2P &&
            suppliersInP2P[_poolTokenAddress].getValueOfKey(_account) != inP2P;
        if (isInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (isInP2PAndValueChanged || !isInP2P)) {
            if (numberOfSuppliersInP2P <= NMAX) {
                numberOfSuppliersInP2P++;
                suppliersInP2P[_poolTokenAddress].insert(_account, inP2P);
            } else {
                (uint256 minimum, address minimumAccount) = suppliersInP2P[_poolTokenAddress]
                    .getMinimum();
                if (inP2P > minimum) {
                    suppliersInP2P[_poolTokenAddress].remove(minimumAccount);
                    suppliersInP2PBuffer[_poolTokenAddress].add(minimumAccount);
                    suppliersInP2P[_poolTokenAddress].insert(_account, inP2P);
                } else suppliersInP2PBuffer[_poolTokenAddress].add(_account);
            }
        }
        if (inP2P == 0 && suppliersInP2PBuffer[_poolTokenAddress].contains(_account))
            suppliersInP2PBuffer[_poolTokenAddress].remove(_account);

        // Add user to the trees if possible
        if (
            suppliersOnPoolBuffer[_poolTokenAddress].length() > 0 && numberOfSuppliersOnPool <= NMAX
        ) {
            address account = suppliersOnPoolBuffer[_poolTokenAddress].at(0);
            uint256 value = supplyBalanceInOf[_poolTokenAddress][account].onPool;
            suppliersOnPoolBuffer[_poolTokenAddress].remove(account);
            suppliersOnPool[_poolTokenAddress].insert(account, value);
        }
        if (
            suppliersInP2PBuffer[_poolTokenAddress].length() > 0 && numberOfSuppliersInP2P <= NMAX
        ) {
            address account = suppliersInP2PBuffer[_poolTokenAddress].at(0);
            uint256 value = supplyBalanceInOf[_poolTokenAddress][account].inP2P;
            suppliersInP2PBuffer[_poolTokenAddress].remove(account);
            suppliersInP2P[_poolTokenAddress].insert(account, value);
        }
    }
}
