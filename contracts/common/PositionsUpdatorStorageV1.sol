// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import "./libraries/DoubleLinkedList.sol";
import "./interfaces/IPositionsManager.sol";

contract PositionsUpdatorStorageV1 is UUPSUpgradeable, OwnableUpgradeable {
    using DoubleLinkedList for DoubleLinkedList.List;

    /* Storage */

    uint256 public maxIterations;
    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in P2P.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on pool.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in P2P.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on pool.

    IPositionsManager public positionsManager;

    modifier onlyPositionsManager() {
        require(msg.sender == address(positionsManager), "only-positions-manager");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyPositionsManager {}
}
