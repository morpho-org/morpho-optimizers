// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "./interfaces/ILensExtension.sol";
import "../interfaces/IMorpho.sol";
import "./interfaces/ILens.sol";

import "@morpho-dao/morpho-utils/math/CompoundMath.sol";
import "../libraries/InterestRatesModel.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage is ILens, Initializable {
    /// CONSTANTS ///

    uint256 public constant MAX_BASIS_POINTS = 100_00; // 100% (in basis points).
    uint256 public constant WAD = 1e18;

    /// IMMUTABLES ///

    IMorpho public immutable morpho;
    IComptroller public immutable comptroller;
    IRewardsManager public immutable rewardsManager;
    ILensExtension internal immutable lensExtension;

    /// STORAGE ///

    address private deprecatedMorpho;
    address private deprecatedComptroller;
    address private deprecatedRewardsManager;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @param _lensExtension The address of the Lens extension.
    constructor(address _lensExtension) {
        lensExtension = ILensExtension(_lensExtension);
        morpho = IMorpho(lensExtension.morpho());
        comptroller = IComptroller(morpho.comptroller());
        rewardsManager = IRewardsManager(morpho.rewardsManager());
    }
}
