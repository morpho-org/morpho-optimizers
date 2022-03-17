// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {ICToken, IComptroller, ICompoundOracle} from "../interfaces/compound/ICompound.sol";
import "../interfaces/IMarketsManagerForCompound.sol";
import "../interfaces/IMatchingEngineForCompound.sol";
import "../interfaces/IRewardsManagerForCompound.sol";
import "../../common/interfaces/ISwapManager.sol";

import "../../common/libraries/DoubleLinkedList.sol";
import "../libraries/CompoundMath.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract PositionsManagerForCompoundStorage is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
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
        uint256 onPool; // In scaled balance.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's p2pUnit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when users are in Compound. Multiply by current borrowIndex to get the underlying amount.
    }

    // Max gas to consume for supply, borrow, withdraw and repay functions.
    struct MaxGas {
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

    /// STORAGE ///

    MaxGas public maxGas; // Max gas to consume within loops in matching engine functions.
    uint8 public NDS; // Max number of iterations in the data structure sorting process.
    uint8 public constant CTOKEN_DECIMALS = 8; // The number of decimals for cToken.
    uint16 public constant MAX_BASIS_POINTS = 10000; // 100% in basis points.
    uint16 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // 50% in basis points.
    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // For a given market, the suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // For a given market, the suppliers on Compound.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // For a given market, the borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // For a given market, the borrowers on Compound.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of a user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of a user.
    mapping(address => mapping(address => bool)) public userMembership; // Whether the user is in the market or not.
    mapping(address => address[]) public enteredMarkets; // The markets entered by a user.
    mapping(address => Delta) public deltas; // Delta parameters for each market.
    mapping(address => bool) public paused; // Whether a market is paused or not.

    IComptroller public comptroller;
    IMarketsManagerForCompound public marketsManager;
    IMatchingEngineForCompound public matchingEngine;
    IRewardsManagerForCompound public rewardsManager;
    ISwapManager public swapManager;
    address public treasuryVault;
}
