// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPositionsManagerForCompound.sol";
import "../interfaces/IMarketsManagerForCompound.sol";
import "../interfaces/compound/ICompound.sol";
import "../interfaces/IInterestRates.sol";
import "../../common/diamond/libraries/LibDiamond.sol";

/// TYPE STRUCTS ///

struct LastPoolIndexes {
    uint256 lastSupplyPoolIndex; // Last supply pool index (current exchange rate) stored.
    uint256 lastBorrowPoolIndex; // Last borrow pool index (borrow index) stored.
}

/// STORAGE STRUCTS ///

struct MarketsStorage {
    address[] marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) isCreated; // Whether or not this market is created.
    mapping(address => uint256) reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    mapping(address => uint256) supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying (in wad).
    mapping(address => uint256) borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying (in wad).
    mapping(address => uint256) lastUpdateBlockNumber; // The last time the P2P exchange rates were updated.
    mapping(address => LastPoolIndexes) lastPoolIndexes; // Last pool index stored.
    mapping(address => bool) noP2P; // Whether to put users on pool or not for the given market.
    IPositionsManagerForCompound positionsManager;
    IInterestRates interestRates;
    IComptroller comptroller;
}

library LibStorage {
    /// STORAGE POSITIONS ///
    bytes32 constant MARKETS_STORAGE_POSITION = keccak256("morpho.storage.markets");

    /// STORAGE POINTER GETTERS ///
    function marketsStorage() internal pure returns (MarketsStorage storage ms) {
        bytes32 position = MARKETS_STORAGE_POSITION;
        assembly {
            ms.slot := position
        }
    }
}

/**
 * The `WithStorageAndModifiers` contract provides a base contract for Facet contracts to inherit.
 *
 * It provides internal helpers to access the storage structs, which reduces
 * calls like `LibStorage.gameStorage()` to just `gs()`.
 *
 * To understand why the storage stucts must be accessed using a function instead of a
 * state variable, please refer to the documentation above `LibStorage` in this file.
 */
contract WithStorageAndModifiers {
    /// COMMON CONSTANTS ///
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }
}
