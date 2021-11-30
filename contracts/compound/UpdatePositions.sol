// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./PositionsManagerStorageForCompound.sol";

/**
 *  @title UpdatePositions.
 *  @dev Allows to move the logic from the positions manager to this contract.
 */
contract UpdatePositions is ReentrancyGuard, PositionsManagerStorageForCompound {
    using RedBlackBinaryTree for RedBlackBinaryTree.Tree;
    using EnumerableSet for EnumerableSet.AddressSet;

    /** @dev Updates borrowers tree with the new balances of a given account.
     *  @param _cTokenAddress The address of the market on which Morpho want to update the borrower lists.
     *  @param _account The address of the borrower to move.
     */
    function updateBorrowerList(address _cTokenAddress, address _account) external {
        uint256 onPool = borrowBalanceInOf[_cTokenAddress][_account].onPool;
        uint256 inP2P = borrowBalanceInOf[_cTokenAddress][_account].inP2P;
        uint256 numberOfBorrowersOnPool = borrowersOnPool[_cTokenAddress].numberOfKeys();
        uint256 numberOfBorrowersInP2P = borrowersInP2P[_cTokenAddress].numberOfKeys();
        bool isOnPool = borrowersOnPool[_cTokenAddress].keyExists(_account);
        bool isInP2P = borrowersInP2P[_cTokenAddress].keyExists(_account);

        // Check pool
        bool isOnPoolAndValueChanged = isOnPool &&
            borrowersOnPool[_cTokenAddress].getValueOfKey(_account) != onPool;
        if (isOnPoolAndValueChanged) borrowersOnPool[_cTokenAddress].remove(_account);
        if (onPool > 0 && (isOnPoolAndValueChanged || !isOnPool)) {
            if (numberOfBorrowersOnPool <= NMAX) {
                numberOfBorrowersOnPool++;
                borrowersOnPool[_cTokenAddress].insert(_account, onPool);
            } else {
                (uint256 minimum, address minimumAccount) = borrowersOnPool[_cTokenAddress]
                    .getMinimum();
                if (onPool > minimum) {
                    borrowersOnPool[_cTokenAddress].remove(minimumAccount);
                    borrowersOnPoolBuffer[_cTokenAddress].add(minimumAccount);
                    borrowersOnPoolBuffer[_cTokenAddress].remove(_account);
                    borrowersOnPool[_cTokenAddress].insert(_account, onPool);
                } else borrowersOnPoolBuffer[_cTokenAddress].add(_account);
            }
        }
        if (onPool == 0 && borrowersOnPoolBuffer[_cTokenAddress].contains(_account))
            borrowersOnPoolBuffer[_cTokenAddress].remove(_account);

        // Check P2P
        bool isInP2PAndValueChanged = isInP2P &&
            borrowersInP2P[_cTokenAddress].getValueOfKey(_account) != inP2P;
        if (isInP2PAndValueChanged) borrowersInP2P[_cTokenAddress].remove(_account);
        if (inP2P > 0 && (isInP2PAndValueChanged || !isInP2P)) {
            if (numberOfBorrowersInP2P <= NMAX) {
                numberOfBorrowersInP2P++;
                borrowersInP2P[_cTokenAddress].insert(_account, inP2P);
            } else {
                (uint256 minimum, address minimumAccount) = borrowersInP2P[_cTokenAddress]
                    .getMinimum();
                if (inP2P > minimum) {
                    borrowersInP2P[_cTokenAddress].remove(minimumAccount);
                    borrowersInP2PBuffer[_cTokenAddress].add(minimumAccount);
                    borrowersInP2PBuffer[_cTokenAddress].remove(_account);
                    borrowersInP2P[_cTokenAddress].insert(_account, inP2P);
                } else borrowersInP2PBuffer[_cTokenAddress].add(_account);
            }
        }
        if (inP2P == 0 && borrowersInP2PBuffer[_cTokenAddress].contains(_account))
            borrowersInP2PBuffer[_cTokenAddress].remove(_account);

        // Add user to the trees if possible
        if (borrowersOnPoolBuffer[_cTokenAddress].length() > 0 && numberOfBorrowersOnPool <= NMAX) {
            address account = borrowersOnPoolBuffer[_cTokenAddress].at(0);
            uint256 value = borrowBalanceInOf[_cTokenAddress][account].onPool;
            borrowersOnPoolBuffer[_cTokenAddress].remove(account);
            borrowersOnPool[_cTokenAddress].insert(account, value);
        }
        if (borrowersInP2PBuffer[_cTokenAddress].length() > 0 && numberOfBorrowersInP2P <= NMAX) {
            address account = borrowersInP2PBuffer[_cTokenAddress].at(0);
            uint256 value = borrowBalanceInOf[_cTokenAddress][account].inP2P;
            borrowersInP2PBuffer[_cTokenAddress].remove(account);
            borrowersInP2P[_cTokenAddress].insert(account, value);
        }
    }

    /** @dev Updates suppliers tree with the new balances of a given account.
     *  @param _cTokenAddress The address of the market on which Morpho want to update the supplier lists.
     *  @param _account The address of the supplier to move.
     */
    function updateSupplierList(address _cTokenAddress, address _account) external {
        uint256 onPool = supplyBalanceInOf[_cTokenAddress][_account].onPool;
        uint256 inP2P = supplyBalanceInOf[_cTokenAddress][_account].inP2P;
        uint256 numberOfSuppliersOnPool = suppliersOnPool[_cTokenAddress].numberOfKeys();
        uint256 numberOfSuppliersInP2P = suppliersInP2P[_cTokenAddress].numberOfKeys();
        bool isOnPool = suppliersOnPool[_cTokenAddress].keyExists(_account);
        bool isInP2P = suppliersInP2P[_cTokenAddress].keyExists(_account);

        // Check pool
        bool isOnPoolAndValueChanged = isOnPool &&
            suppliersOnPool[_cTokenAddress].getValueOfKey(_account) != onPool;
        if (isOnPoolAndValueChanged) suppliersOnPool[_cTokenAddress].remove(_account);
        if (onPool > 0 && (isOnPoolAndValueChanged || !isOnPool)) {
            if (numberOfSuppliersOnPool <= NMAX) {
                numberOfSuppliersOnPool++;
                suppliersOnPool[_cTokenAddress].insert(_account, onPool);
            } else {
                (uint256 minimum, address minimumAccount) = suppliersOnPool[_cTokenAddress]
                    .getMinimum();
                if (onPool > minimum) {
                    suppliersOnPool[_cTokenAddress].remove(minimumAccount);
                    suppliersOnPoolBuffer[_cTokenAddress].add(minimumAccount);
                    suppliersOnPoolBuffer[_cTokenAddress].remove(_account);
                    suppliersOnPool[_cTokenAddress].insert(_account, onPool);
                } else suppliersOnPoolBuffer[_cTokenAddress].add(_account);
            }
        }
        if (onPool == 0 && suppliersOnPoolBuffer[_cTokenAddress].contains(_account))
            suppliersOnPoolBuffer[_cTokenAddress].remove(_account);

        // Check P2P
        bool isInP2PAndValueChanged = isInP2P &&
            suppliersInP2P[_cTokenAddress].getValueOfKey(_account) != inP2P;
        if (isInP2PAndValueChanged) suppliersInP2P[_cTokenAddress].remove(_account);
        if (inP2P > 0 && (isInP2PAndValueChanged || !isInP2P)) {
            if (numberOfSuppliersInP2P <= NMAX) {
                numberOfSuppliersInP2P++;
                suppliersInP2P[_cTokenAddress].insert(_account, inP2P);
            } else {
                (uint256 minimum, address minimumAccount) = suppliersInP2P[_cTokenAddress]
                    .getMinimum();
                if (inP2P > minimum) {
                    suppliersInP2P[_cTokenAddress].remove(minimumAccount);
                    suppliersInP2PBuffer[_cTokenAddress].add(minimumAccount);
                    suppliersInP2PBuffer[_cTokenAddress].remove(_account);
                    suppliersInP2P[_cTokenAddress].insert(_account, inP2P);
                } else suppliersInP2PBuffer[_cTokenAddress].add(_account);
            }
        }
        if (inP2P == 0 && suppliersInP2PBuffer[_cTokenAddress].contains(_account))
            suppliersInP2PBuffer[_cTokenAddress].remove(_account);

        // Add user to the trees if possible
        if (suppliersOnPoolBuffer[_cTokenAddress].length() > 0 && numberOfSuppliersOnPool <= NMAX) {
            address account = suppliersOnPoolBuffer[_cTokenAddress].at(0);
            uint256 value = supplyBalanceInOf[_cTokenAddress][account].onPool;
            suppliersOnPoolBuffer[_cTokenAddress].remove(account);
            suppliersOnPool[_cTokenAddress].insert(account, value);
        }
        if (suppliersInP2PBuffer[_cTokenAddress].length() > 0 && numberOfSuppliersInP2P <= NMAX) {
            address account = suppliersInP2PBuffer[_cTokenAddress].at(0);
            uint256 value = supplyBalanceInOf[_cTokenAddress][account].inP2P;
            suppliersInP2PBuffer[_cTokenAddress].remove(account);
            suppliersInP2P[_cTokenAddress].insert(account, value);
        }
    }
}
