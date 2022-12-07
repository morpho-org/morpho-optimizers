// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";

import "@morpho-dao/morpho-utils/math/CompoundMath.sol";
import "../libraries/InterestRatesModel.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage {
    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 100_00; // 100% (in basis points).
    uint256 public constant WAD = 1e18;

    IMorpho public immutable morpho;
    IComptroller public immutable comptroller;
    IRewardsManager public immutable rewardsManager;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @param _morpho The address of the main Morpho contract.
    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        comptroller = IComptroller(morpho.comptroller());
        rewardsManager = IRewardsManager(morpho.rewardsManager());
    }
}
