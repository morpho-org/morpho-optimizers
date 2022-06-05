// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

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
        uint256 inP2P; // In supplier's peer-to-peer unit, a unit that grows in underlying value, to keep track of the interests earned by suppliers in peer-to-peer. Multiply by the peer-to-peer supply index to get the underlying amount. (in wad)
        uint256 onPool; // In scaled balance. Multiply by the pool supply index to get the underlying amount. (in wad)
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's peer-to-peer unit, a unit that grows in underlying value, to keep track of the interests paid by borrowers in peer-to-peer. Multiply by the peer-to-peer borrow index to get the underlying amount. (in wad)
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when borrowers are on Compound. Multiply by the pool borrow index to get the underlying amount. (in wad)
    }

    // Max gas to consume during the matching process for supply, borrow, withdraw and repay functions.
    struct MaxGasForMatching {
        uint64 supply;
        uint64 borrow;
        uint64 withdraw;
        uint64 repay;
    }

    struct Delta {
        uint256 p2pSupplyDelta; // Difference between the stored peer-to-peer supply amount and the real peer-to-peer supply amount (in aToken). (in wad)
        uint256 p2pBorrowDelta; // Difference between the stored peer-to-peer borrow amount and the real peer-to-peer borrow amount (in adUnit). (in wad)
        uint256 p2pSupplyAmount; // Sum of all stored peer-to-peer supply (in peer-to-peer unit). (in wad)
        uint256 p2pBorrowAmount; // Sum of all stored peer-to-peer borrow (in peer-to-peer unit). (in wad)
    }

    struct AssetLiquidityData {
        uint256 reserveDecimals; // The number of decimals of the underlying token.
        uint256 tokenUnit; // The token unit considering its decimals.
        uint256 liquidationThreshold; // The liquidation threshold applied on this token (in basis point).
        uint256 ltv; // The LTV applied on this token (in basis point).
        uint256 underlyingPrice; // The price of the token (In base currency in wad).
        uint256 collateralValue; // The collateral value of the asset (In base currency in wad).
        uint256 debtValue; // The debt value of the asset (In base currency in wad).
    }

    struct LiquidityData {
        uint256 healthFactor; // The health factor of the user (in basis points).
        uint256 collateralValue; // The collateral value (In base currency in wad).
        uint256 maxLoanToValue; // The max loan to value (In base currency in wad).
        uint256 liquidationThresholdValue; // The liquidation threshold value (In base currency in wad).
        uint256 debtValue; // The debt value (In base currency in wad).
    }

    // Variables are packed together to save gas (will not exceed their limit during Morpho's lifetime).
    struct PoolIndexes {
        uint32 lastUpdateTimestamp; // The last time the peer-to-peer indexes were updated.
        uint112 poolSupplyIndex; // Last pool supply index (in ray).
        uint112 poolBorrowIndex; // Last pool borrow index (in ray).
    }

    struct MarketParameters {
        uint16 reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10 000). The default value is 0.
        uint16 p2pIndexCursor; // Position of the peer-to-peer rate in the pool's spread. Determine the weights of the weighted arithmetic average in the indexes computations ((1 - p2pIndexCursor) * r^S + p2pIndexCursor * r^B) (in basis point).
    }

    struct MarketStatus {
        bool isCreated; // Whether or not this market is created.
        bool isPaused; // Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
        bool isPartiallyPaused; // Whether the market is partially paused or not (only supply and borrow are frozen).
    }
}