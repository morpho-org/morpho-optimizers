// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {HeapOrdering} from "@morpho-dao/morpho-data-structures/HeapOrdering.sol";
import {IPoolAddressesProvider, IRewardsController, IPool, IIncentivesVault, IRewardsManager} from "../interfaces/Interfaces.sol";
import {Types} from "../libraries/Libraries.sol";

library MorphoStorage {
    /// CONSTANTS ///

    uint16 constant NO_REFERRAL_CODE = 0;
    uint256 constant VARIABLE_INTEREST_MODE = 2;
    uint256 constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.
    uint256 constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 5_000; // 50% in basis points.
    uint256 constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.
    uint256 constant MAX_NB_OF_MARKETS = 128;
    uint256 constant MAX_LIQUIDATION_CLOSE_FACTOR = 10_000; // 100% in basis points.
    uint256 constant MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 0.95e18; // Health factor below which the positions can be liquidated, whether or not the price oracle sentinel allows the liquidation.
    bytes32 constant BORROWING_MASK =
        0x5555555555555555555555555555555555555555555555555555555555555555;
    bytes32 constant ONE = 0x0000000000000000000000000000000000000000000000000000000000000001;

    /// STORAGE POSITIONS ///

    bytes32 constant MORPHO_GLOBAL_STORAGE_POSITION =
        keccak256("diamond.standard.morpho.global.storage");
    bytes32 constant MORPHO_CONTRACTS_STORAGE_POSITION =
        keccak256("diamond.standard.morpho.contracts.storage");
    bytes32 constant MORPHO_POSITIONS_STORAGE_POSITION =
        keccak256("diamond.standard.morpho.positions.storage");
    bytes32 constant MORPHO_MARKETS_STORAGE_POSITION =
        keccak256("diamond.standard.morpho.markets.storage");

    /// STORAGE LAYOUTS ///

    struct GlobalLayout {
        uint256 maxSortedUsers;
        Types.MaxGasForMatching defaultGasForMatching;
        bool isClaimRewardsPaused;
    }

    struct ContractsLayout {
        IPoolAddressesProvider addressesProvider;
        IRewardsController rewardsController;
        IPool pool;
        IIncentivesVault incentivesVault;
        IRewardsManager rewardsManager;
        address treasuryVault;
    }

    struct PositionsLayout {
        mapping(address => HeapOrdering.HeapArray) suppliersInP2P;
        mapping(address => HeapOrdering.HeapArray) suppliersOnPool;
        mapping(address => HeapOrdering.HeapArray) borrowersInP2P;
        mapping(address => HeapOrdering.HeapArray) borrowersOnPool;
        mapping(address => mapping(address => Types.Balance)) supplyBalanceInOf;
        mapping(address => mapping(address => Types.Balance)) borrowBalanceInOf;
        mapping(address => bytes32) userMarkets;
    }

    struct MarketsLayout {
        address[] marketsCreated;
        mapping(address => uint256) p2pSupplyIndex;
        mapping(address => uint256) p2pBorrowIndex;
        mapping(address => Types.PoolIndexes) poolIndexes;
        mapping(address => Types.Market) market;
        mapping(address => Types.Delta) deltas;
        mapping(address => bytes32) borrowMask;
    }

    /// STORAGE GETTERS ///

    function globalLayout() internal pure returns (GlobalLayout storage g) {
        bytes32 slot = MORPHO_GLOBAL_STORAGE_POSITION;
        assembly {
            g.slot := slot
        }
    }

    function contractsLayout() internal pure returns (ContractsLayout storage l) {
        bytes32 slot = MORPHO_CONTRACTS_STORAGE_POSITION;
        assembly {
            l.slot := slot
        }
    }

    function positionsLayout() internal pure returns (PositionsLayout storage p) {
        bytes32 slot = MORPHO_POSITIONS_STORAGE_POSITION;
        assembly {
            p.slot := slot
        }
    }

    function marketsLayout() internal pure returns (MarketsLayout storage m) {
        bytes32 slot = MORPHO_MARKETS_STORAGE_POSITION;
        assembly {
            m.slot := slot
        }
    }
}
