// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

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
        uint256 inP2P; // In supplier's peer-to-peer unit, a unit that grows in value, to keep track of the interests earned when users are in P2P.
        uint256 onPool; // In cToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's peer-to-peer unit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
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
        uint256 supplyP2PAmount; // Sum of all stored P2P supply (in peer-to-peer unit).
        uint256 borrowP2PAmount; // Sum of all stored P2P borrow (in peer-to-peer unit).
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
        uint16 reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10 000). The default value is 0.
        uint16 p2pIndexCursor; // Position of the peer-to-peer rate in the pool's spread. Determine the weights of the weighted arithmetic average in the indexes computations ((1 - p2pIndexCursor) * r^S + p2pIndexCursor * r^B) (in basis point).
    }

    struct MarketStatuses {
        bool isCreated; // Whether or not this market is created.
        bool isPaused; // Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
        bool isPartiallyPaused; // Whether the market is partially paused or not (only supply and borrow are frozen).
    }
}
