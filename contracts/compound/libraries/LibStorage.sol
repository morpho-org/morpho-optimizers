// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPositionsManagerForCompound.sol";
import "../interfaces/IMarketsManagerForCompound.sol";
import "../interfaces/IRewardsManagerForCompound.sol";
import "../interfaces/IMatchingEngineForCompound.sol";
import "../interfaces/compound/ICompound.sol";
import "../interfaces/IIncentivesVault.sol";

import "../../common/diamond/libraries/LibDiamond.sol";
import "../../common/libraries/DoubleLinkedList.sol";
import "./Types.sol";

/// STORAGE STRUCTS ///

struct ContractStorage {
    uint256 status; // re-entry indicator
}

struct MarketsStorage {
    address[] marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) isCreated; // Whether or not this market is created.
    mapping(address => uint256) reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    mapping(address => uint256) supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying (in wad).
    mapping(address => uint256) borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying (in wad).
    mapping(address => uint256) lastUpdateBlockNumber; // The last time the P2P exchange rates were updated.
    mapping(address => Types.LastPoolIndexes) lastPoolIndexes; // Last pool index stored.
    mapping(address => bool) noP2P; // Whether to put users on pool or not for the given market.
    mapping(address => bool) paused; // Whether a market is paused or not.
}

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
    IRewardsManagerForCompound rewardsManager;
    IIncentivesVault incentivesVault;
    IComptroller comptroller;
    address treasuryVault;
    address cEth;
    address wEth;
}

library LibStorage {
    /// STORAGE POSITIONS ///

    bytes32 public constant CONTRACT_STORAGE_POSITION = keccak256("morpho.storage.contract");

    bytes32 public constant MARKETS_STORAGE_POSITION = keccak256("morpho.storage.markets");

    bytes32 public constant POSITIONS_STORAGE_POSITION = keccak256("morpho.storage.positions");

    /// STORAGE POINTER GETTERS ///

    function contractStorage() internal pure returns (ContractStorage storage cs) {
        bytes32 position = CONTRACT_STORAGE_POSITION;
        assembly {
            cs.slot := position
        }
    }

    function marketsStorage() internal pure returns (MarketsStorage storage ms) {
        bytes32 position = MARKETS_STORAGE_POSITION;
        assembly {
            ms.slot := position
        }
    }

    function positionsStorage() internal pure returns (PositionsStorage storage ps) {
        bytes32 position = POSITIONS_STORAGE_POSITION;
        assembly {
            ps.slot := position
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

    uint8 public constant CTOKEN_DECIMALS = 8;
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).
    uint16 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5_000; // 50% in basis points

    /// REENTRY GUARD VARS ///

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    /// MODIFIERS ///

    modifier onlyGovernance() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(cs().status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        cs().status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        cs().status = _NOT_ENTERED;
    }

    /// STORAGE GETTERS ///

    function cs() internal pure returns (ContractStorage storage) {
        return LibStorage.contractStorage();
    }

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }
}
