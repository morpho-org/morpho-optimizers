// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IMorpho.sol";

import {Math} from "@morpho-dao/morpho-utils/math/Math.sol";
import {CompoundMath} from "@morpho-dao/morpho-utils/math/CompoundMath.sol";
import {PercentageMath} from "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import {InterestRatesModel} from "../libraries/InterestRatesModel.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage is Initializable {
    /// STORAGE ///

    IMorpho public morpho;
    IComptroller public comptroller;
    IRewardsManager public rewardsManager;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}
}
