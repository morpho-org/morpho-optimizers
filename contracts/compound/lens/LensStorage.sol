// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage is Initializable {
    /// STORAGE ///

    uint256 public constant BLOCKS_PER_YEAR = 10_000; // Compound's BLOCKS_PER_YEAR.
    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis points).
    uint256 public constant WAD = 1e18;

    IMorpho public morpho;
    IComptroller public comptroller;
    IRewardsManager public rewardsManager;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}
}
