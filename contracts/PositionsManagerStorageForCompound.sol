// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./libraries/RedBlackBinaryTree.sol";
import {IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IMarketsManagerForCompound.sol";
import "./interfaces/IUpdatePositions.sol";

/**
 *  @title MorphoPositionsManagerForComp.
 *  @dev Smart contract interacting with Comp to enable P2P supply/borrow positions that can fallback on Comp's pool using cToken tokens.
 */
contract PositionsManagerStorageForCompound {
    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In p2pUnit, a unit that grows in value, to keep track of the interests/debt increase when users are in p2p.
        uint256 onPool; // In cToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In p2pUnit.
        uint256 onPool; // In cdUnit, a unit that grows in value, to keep track of the debt increase when users are in Comp. Multiply by current borrowIndex to get the underlying amount.
    }

    /* Storage */

    uint16 public NMAX = 1000;
    uint8 public constant CTOKEN_DECIMALS = 8;
    mapping(address => RedBlackBinaryTree.Tree) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) internal suppliersOnPool; // Suppliers on Comp.
    mapping(address => RedBlackBinaryTree.Tree) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) internal borrowersOnPool; // Borrowers on Comp.
    mapping(address => EnumerableSet.AddressSet) internal suppliersInP2PBuffer; // Buffer of suppliers in peer-to-peer.
    mapping(address => EnumerableSet.AddressSet) internal suppliersOnPoolBuffer; // Buffer of suppliers on Comp.
    mapping(address => EnumerableSet.AddressSet) internal borrowersInP2PBuffer; // Buffer of borrowers in peer-to-peer.
    mapping(address => EnumerableSet.AddressSet) internal borrowersOnPoolBuffer; // Buffer of borrowers on Comp.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => EnumerableSet.AddressSet) internal enteredMarkets; // Markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IUpdatePositions public updatePositions;
    IComptroller public comptroller;
    IMarketsManagerForCompound public marketsManagerForCompound;
}
