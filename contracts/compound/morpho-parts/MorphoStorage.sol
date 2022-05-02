// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IPositionsManager.sol";
import "../interfaces/IIncentivesVault.sol";
import "../interfaces/IRewardsManager.sol";
import "../interfaces/IInterestRates.sol";

import "../../common/libraries/DoubleLinkedList.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MorphoStorage is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// ENUMS ///

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    /// STRUCTS ///

    struct SupplyBalance {
        uint256 inP2P; // In supplier's p2pUnit, a unit that grows in value, to keep track of the interests earned when users are in P2P.
        uint256 onPool; // In cToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's p2pUnit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
        uint256 onPool; // In cdUnit, a unit that grows in value, to keep track of the debt increase when users are in Compound. Multiply by current borrowIndex to get the underlying amount.
    }

    // Max gas to consume during the matching process for supply, borrow, withdraw and repay functions.
    struct MaxGasForMatching {
        uint64 supply;
        uint64 borrow;
        uint64 withdraw;
        uint64 repay;
    }

    struct Delta {
        uint256 supplyP2PDelta; // Difference between the stored P2P supply amount and the real P2P supply amount (in scaled balance).
        uint256 borrowP2PDelta; // Difference between the stored P2P borrow amount and the real P2P borrow amount (in adUnit).
        uint256 supplyP2PAmount; // Sum of all stored P2P supply (in P2P unit).
        uint256 borrowP2PAmount; // Sum of all stored P2P borrow (in P2P unit).
    }

    struct AssetLiquidityData {
        uint256 collateralValue; // The collateral value of the asset.
        uint256 maxDebtValue; // The maximum possible debt value of the asset.
        uint256 debtValue; // The debt value of the asset.
        uint256 underlyingPrice; // The price of the token.
        uint256 collateralFactor; // The liquidation threshold applied on this token (in basis point).
    }

    struct LiquidityData {
        uint256 collateralValue; // The collateral value.
        uint256 maxDebtValue; // The maximum debt value possible.
        uint256 debtValue; // The debt value.
    }

    // Struct to avoid stack too deep.
    struct LiquidateVars {
        uint256 debtValue;
        uint256 maxDebtValue;
        uint256 borrowBalance;
        uint256 supplyBalance;
        uint256 collateralPrice;
        uint256 borrowedPrice;
        uint256 amountToSeize;
    }

    struct LastPoolIndexes {
        uint32 lastUpdateBlockNumber; // The last time the P2P indexes were updated.
        uint112 lastSupplyPoolIndex; // Last pool supply index.
        uint112 lastBorrowPoolIndex; // Last pool borrow index.
    }

    struct MarketParameters {
        uint16 reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
        uint16 p2pIndexCursor; // Position of the peer-to-peer rate in the pool's spread. Determine the weights of the weighted arithmetic average in the indexes computations ((1 - p2pIndexCursor) * r^S + p2pIndexCursor * r^B) (in basis point).
    }

    struct MarketStatuses {
        bool isCreated; // Whether or not this market is created.
        bool isPaused; // Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
        bool isPartiallyPaused; // Whether the market is partially paused or not (only supply and borrow are frozen).
    }

    /// GLOBAL STORAGE ///

    uint8 public constant CTOKEN_DECIMALS = 8; // The number of decimals for cToken.
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.
    uint16 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5_000; // 50% in basis points.
    uint256 public constant WAD = 1e18;

    bool public isCompRewardsActive; // True if the Compound reward is active.
    uint256 public maxSortedUsers; // The max number of users to sort in the data structure.
    uint256 public dustThreshold; // The minimum amount to keep in the data stucture.
    MaxGasForMatching public maxGasForMatching; // Max gas to consume within loops in matching engine functions.

    /// POSITIONS STORAGE ///

    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // For a given market, the suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // For a given market, the suppliers on Compound.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // For a given market, the borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // For a given market, the borrowers on Compound.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of a user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of a user.
    mapping(address => mapping(address => bool)) public userMembership; // Whether the user is in the market or not.
    mapping(address => address[]) public enteredMarkets; // The markets entered by a user.

    /// MARKETS STORAGE ///

    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) public noP2P; // Whether to put users on pool or not for the given market.
    mapping(address => uint256) public p2pSupplyIndex; // Current index from supply p2pUnit to underlying (in wad).
    mapping(address => uint256) public p2pBorrowIndex; // Current index from borrow p2pUnit to underlying (in wad).
    mapping(address => LastPoolIndexes) public lastPoolIndexes; // Last pool index stored.
    mapping(address => MarketParameters) public marketParameters; // Market parameters.
    mapping(address => MarketStatuses) public marketStatuses; // Whether a market is paused or partially paused or not.
    mapping(address => Delta) public deltas; // Delta parameters for each market.

    /// CONTRACTS AND ADDRESSES ///

    IPositionsManager public positionsManager;
    IIncentivesVault public incentivesVault;
    IRewardsManager public rewardsManager;
    IInterestRates public interestRates;
    IComptroller public comptroller;
    address public treasuryVault;
    address public cEth;
    address public wEth;
}
