// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IIncentivesVault.sol";
import "../interfaces/IMarketsManager.sol";
import "../interfaces/IRewardsManager.sol";
import "../interfaces/IWETH.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "../../common/libraries/DoubleLinkedList.sol";
import "../libraries/CompoundMath.sol";
import "../libraries/LibStorage.sol";
import "../libraries/Types.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract PositionsManagerStorage is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// STORAGE ///

    uint8 public constant CTOKEN_DECIMALS = 8; // The number of decimals for cToken.
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% in basis points.
    uint16 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5_000; // 50% in basis points.

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }
}
