// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";

import "../libraries/CompoundMath.sol";
import "../libraries/InterestRatesModel.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage is Initializable {
    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 100_00; // 100% (in basis points).
    uint256 public constant WAD = 1e18;

    IMorpho public morpho;
    IComptroller public comptroller;
    IRewardsManager public rewardsManager;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}
}
