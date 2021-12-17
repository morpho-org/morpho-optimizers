// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./libraries/DoubleLinkedList.sol";
import "./interfaces/IPositionsManager.sol";
import "./interfaces/IPositionsUpdator.sol";
import "./interfaces/IPositionsUpdatorLogic.sol";

contract PositionsUpdatorStorage is Ownable {
    using DoubleLinkedList for DoubleLinkedList.List;

    /* Storage */

    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in P2P.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on pool.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in P2P.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on poon.
    IPositionsManager public positionsManager;
    IPositionsUpdatorLogic public positionsUpdatorLogic;
    uint256 NMAX = 20;
}
