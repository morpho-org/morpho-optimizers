// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

library MarketLib {
    function isCreated(Types.Market storage _market) internal view returns (bool) {
        return _market.underlyingToken != address(0);
    }

    function isCreatedMemory(Types.Market memory _market) internal pure returns (bool) {
        return _market.underlyingToken != address(0);
    }

    function isPausedMemory(Types.Market memory _market) internal pure returns (bool) {
        return (_market.isSupplyPaused &&
            _market.isBorrowPaused &&
            _market.isWithdrawPaused &&
            _market.isRepayPaused);
    }

    function isPartiallyPausedMemory(Types.Market memory _market) internal pure returns (bool) {
        return (_market.isSupplyPaused && _market.isBorrowPaused);
    }
}

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
        uint256 p2pSupplyDelta; // Difference between the stored peer-to-peer supply amount and the real peer-to-peer supply amount (in aToken).
        uint256 p2pBorrowDelta; // Difference between the stored peer-to-peer borrow amount and the real peer-to-peer borrow amount (in adUnit).
        uint256 p2pSupplyAmount; // Sum of all stored peer-to-peer supply (in peer-to-peer unit).
        uint256 p2pBorrowAmount; // Sum of all stored peer-to-peer borrow (in peer-to-peer unit).
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

    // Variables are packed together to save gas (will not exceed their limit during Morpho's lifetime).
    struct PoolIndexes {
        uint32 lastUpdateTimestamp; // The last time the local pool and peer-to-peer indexes were updated.
        uint112 poolSupplyIndex; // Last pool supply index (in ray).
        uint112 poolBorrowIndex; // Last pool borrow index (in ray).
    }

    struct Market {
        address underlyingToken; // The underlying address of the market.
        uint16 reserveFactor; // Proportion of the additional interest earned being matched peer-to-peer on Morpho compared to being on the pool. It is sent to the DAO for each market. The default value is 0. In basis point (100% = 10 000).
        uint16 p2pIndexCursor; // Position of the peer-to-peer rate in the pool's spread. Determine the weights of the weighted arithmetic average in the indexes computations ((1 - p2pIndexCursor) * r^S + p2pIndexCursor * r^B) (in basis point).
        bool isP2PDisabled; // Whether the market's peer-to-peer is open or not.
        bool isSupplyPaused; // Whether the supply is paused or not.
        bool isBorrowPaused; // Whether the borrow is paused or not
        bool isWithdrawPaused; // Whether the withdraw is paused or not. Note that a "withdraw" is still possible using a liquidation (if not paused).
        bool isRepayPaused; // Whether the repay is paused or not. Note that a "repay" is still possible using a liquidation (if not paused).
        bool isLiquidateCollateralPaused; // Whether the liquidation on this market as collateral is paused or not.
        bool isLiquidateBorrowPaused; // Whether the liquidatation on this market as borrow is paused or not.
        bool isDeprecated; // Whether a market is deprecated or not.
    }

    struct LiquidityStackVars {
        address poolToken;
        uint256 poolTokensLength;
        bytes32 userMarkets;
        bytes32 borrowMask;
        address underlyingToken;
        uint256 underlyingPrice;
    }

    struct GrowthFactors {
        uint256 poolSupplyGrowthFactor; // The pool's supply index growth factor (in ray).
        uint256 poolBorrowGrowthFactor; // The pool's borrow index growth factor (in ray).
        uint256 p2pSupplyGrowthFactor; // Peer-to-peer supply index growth factor (in ray).
        uint256 p2pBorrowGrowthFactor; // Peer-to-peer borrow index growth factor (in ray).
    }

    struct P2PIndexComputeParams {
        uint256 lastP2PSupplyIndex; // The peer-to-peer supply index at last update.
        uint256 lastP2PBorrowIndex; // The peer-to-peer borrow index at last update.
        uint256 poolSupplyIndex; // The current pool supply index.
        uint256 poolBorrowIndex; // The current pool borrow index.
        uint256 lastPoolSupplyIndex; // The pool supply index at last update.
        uint256 lastPoolBorrowIndex; // The pool borrow index at last update.
        uint256 reserveFactor; // The reserve factor percentage (10 000 = 100%).
        uint256 p2pIndexCursor; // The peer-to-peer index cursor (10 000 = 100%).
        Types.Delta delta; // The deltas and peer-to-peer amounts.
    }
}
