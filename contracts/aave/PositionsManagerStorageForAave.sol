// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./libraries/RedBlackBinaryTree.sol";
import "./interfaces/IUpdatePositions.sol";
import "./interfaces/IMarketsManagerForAave.sol";

/**
 *  @title MorphoPositionsManagerForComp.
 *  @dev Smart contract interacting with Comp to enable P2P supply/borrow positions that can fallback on Comp's pool using cToken tokens.
 */
contract PositionsManagerStorageForAave {
    /* Structs */

    struct SupplyBalance {
        uint256 inP2P; // In p2pUnit, a unit that grows in value, to keep track of the interests/debt increase when users are in p2p.
        uint256 onPool; // In aToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In p2pUnit.
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when users are in Aave. Multiply by current borrowIndex to get the underlying amount.
    }

    /* Storage */

    uint16 public NMAX = 1000;
    uint256 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // In basis points.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.
    mapping(address => RedBlackBinaryTree.Tree) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) internal suppliersOnPool; // Suppliers on Aave.
    mapping(address => RedBlackBinaryTree.Tree) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => RedBlackBinaryTree.Tree) internal borrowersOnPool; // Borrowers on Aave.
    mapping(address => EnumerableSet.AddressSet) internal suppliersInP2PBuffer; // Buffer of suppliers in peer-to-peer.
    mapping(address => EnumerableSet.AddressSet) internal suppliersOnPoolBuffer; // Buffer of suppliers on Aave.
    mapping(address => EnumerableSet.AddressSet) internal borrowersInP2PBuffer; // Buffer of borrowers in peer-to-peer.
    mapping(address => EnumerableSet.AddressSet) internal borrowersOnPoolBuffer; // Buffer of borrowers on Aave.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of user.
    mapping(address => mapping(address => bool)) public accountMembership; // Whether the account is in the market or not.
    mapping(address => address[]) public enteredMarkets; // Markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IUpdatePositions public updatePositions;
    IMarketsManagerForAave public marketsManagerForAave;
    ILendingPoolAddressesProvider public addressesProvider;
    IProtocolDataProvider public dataProvider;
    ILendingPool public lendingPool;
}
