// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IIncentivesVault.sol";
import "../interfaces/IMarketsManager.sol";
import "../interfaces/IRewardsManager.sol";

import "../../common/libraries/DoubleLinkedList.sol";
import "../libraries/Types.sol";

struct PositionsStorage {
    uint8 NDS; // Max number of iterations in the data structure sorting process..
    bool isCompRewardsActive; // True if the Compound reward is active.
    Types.MaxGas maxGas; // Max gas to consume within loops in matching engine functions.
    mapping(address => DoubleLinkedList.List) suppliersInP2P; // For a given market, the suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) suppliersOnPool; // For a given market, the suppliers on Compound.
    mapping(address => DoubleLinkedList.List) borrowersInP2P; // For a given market, the borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) borrowersOnPool; // For a given market, the borrowers on Compound.
    mapping(address => mapping(address => Types.SupplyBalance)) supplyBalanceInOf; // For a given market, the supply balance of a user.
    mapping(address => mapping(address => Types.BorrowBalance)) borrowBalanceInOf; // For a given market, the borrow balance of a user.
    mapping(address => mapping(address => bool)) userMembership; // Whether the user is in the market or not.
    mapping(address => address[]) enteredMarkets; // The markets entered by a user.
    mapping(address => Types.Delta) deltas; // Delta parameters for each market.
    IIncentivesVault incentivesVault;
    IMarketsManager marketsManager;
    IRewardsManager rewardsManager;
    IComptroller comptroller;
    address treasuryVault;
    address cEth;
    address wEth;
}

library LibStorage {
    /// STORAGE POSITIONS ///

    bytes32 public constant POSITIONS_STORAGE_POSITION = keccak256("morpho.storage.positions");

    /// STORAGE POINTER GETTERS ///

    function positionsStorage() internal pure returns (PositionsStorage storage ps) {
        bytes32 position = POSITIONS_STORAGE_POSITION;
        assembly {
            ps.slot := position
        }
    }
}
