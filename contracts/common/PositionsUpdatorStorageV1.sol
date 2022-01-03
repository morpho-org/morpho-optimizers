// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/IPositionsManager.sol";

import "./libraries/DoubleLinkedList.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

abstract contract PositionsUpdatorStorageV1 is UUPSUpgradeable, OwnableUpgradeable {
    /* Enums */

    enum UserType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    /* Storage */

    uint256 public maxIterations;
    mapping(uint8 => mapping(address => DoubleLinkedList.List)) internal data;

    IPositionsManager public positionsManager;
}
