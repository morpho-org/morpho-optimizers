// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@morpho-dao/morpho-data-structures/HeapOrdering.sol";

/// @title Types.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @dev Common types and structs used in Morpho contracts.
library Types {
    /// ENUMS ///

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    /// STRUCTS ///

    struct SupplyBalance {
        uint256 inP2P; // In peer-to-peer supply scaled unit, a unit that grows in underlying value, to keep track of the interests earned by suppliers in peer-to-peer. Multiply by the peer-to-peer supply index to get the underlying amount.
        uint256 onPool; // In pool supply scaled unit. Multiply by the pool supply index to get the underlying amount.
    }

    struct BorrowBalance {
        uint256 inP2P; // In peer-to-peer borrow scaled unit, a unit that grows in underlying value, to keep track of the interests paid by borrowers in peer-to-peer. Multiply by the peer-to-peer borrow index to get the underlying amount.
        uint256 onPool; // In pool borrow scaled unit, a unit that grows in value, to keep track of the debt increase when borrowers are on Aave. Multiply by the pool borrow index to get the underlying amount.
    }

    // Max gas to consume during the matching process for supply, borrow, withdraw and repay functions.
    struct MaxGasForMatching {
        uint64 supply;
        uint64 borrow;
        uint64 withdraw;
        uint64 repay;
    }

    struct AssetLiquidityData {
        uint256 decimals; // The number of decimals of the underlying token.
        uint256 tokenUnit; // The token unit considering its decimals.
        uint256 liquidationThreshold; // The liquidation threshold applied on this token (in basis point).
        uint256 ltv; // The LTV applied on this token (in basis point).
        uint256 underlyingPrice; // The price of the token (In base currency in wad).
        uint256 collateral; // The collateral value of the asset (In base currency in wad).
        uint256 debt; // The debt value of the asset (In base currency in wad).
    }

    struct LiquidityData {
        uint256 collateral; // The collateral value (In base currency in wad).
        uint256 maxDebt; // The max debt value (In base currency in wad).
        uint256 liquidationThreshold; // The liquidation threshold value (In base currency in wad).
        uint256 debt; // The debt value (In base currency in wad).
    }

    struct Index {
        uint128 p2pSupplyIndex; // Current index from supply peer-to-peer unit to underlying (in ray).
        uint128 p2pBorrowIndex; // Current index from borrow peer-to-peer unit to underlying (in ray).
        uint128 poolSupplyIndex; // Last pool supply index (in ray).
        uint128 poolBorrowIndex; // Last pool borrow index (in ray).
    }

    struct Delta {
        uint128 p2pSupplyDelta;
        uint128 p2pBorrowDelta;
        uint128 p2pSupplyAmount;
        uint128 p2pBorrowAmount;
    }

    struct Flag {
        bool isP2PDisabled;
        bool isDeprecated;
        bool isSupplyPaused;
        bool isBorrowPaused;
        bool isWithdrawPaused;
        bool isRepayPaused;
        bool isLiquidateCollateralPaused;
        bool isLiquidateBorrowPaused;
    }

    struct MarketData {
        address underlyingToken;
        uint32 reserveFactor;
        uint32 p2pIndexCursor;
        uint32 lastUpdateTimestamp;
        bytes32 borrowMask;
        Index index;
        Delta delta;
        Flag flag;
    }

    struct UserData {
        HeapOrdering.HeapArray suppliersInP2P; // For a given market, the suppliers in peer-to-peer.
        HeapOrdering.HeapArray suppliersOnPool; // For a given market, the suppliers on Aave.
        HeapOrdering.HeapArray borrowersInP2P; // For a given market, the borrowers in peer-to-peer.
        HeapOrdering.HeapArray borrowersOnPool; // For a given market, the borrowers on Aave.
        mapping(address => Types.SupplyBalance) supplyBalanceInOf; // For a given market, the supply balance of a user. aToken -> user -> balances.
        mapping(address => Types.BorrowBalance) borrowBalanceInOf; // For a given market, the borrow balance of a user. aToken -> user -> balances.
    }

    struct LiquidityStackVars {
        address poolToken;
        uint256 poolTokensLength;
        bytes32 userMarkets;
        bytes32 borrowMask;
        address underlyingToken;
        uint256 underlyingPrice;
    }
}
