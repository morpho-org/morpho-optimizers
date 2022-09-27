// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/aave/IPool.sol";
import "../interfaces/IMorpho.sol";
import "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import "@aave/core-v3/contracts/interfaces/IAToken.sol";

import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

import "../libraries/aave/ReserveConfiguration.sol";
import "../libraries/aave/UserConfiguration.sol";
import "../libraries/aave/DataTypes.sol";

import "../libraries/InterestRatesModel.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage {
    /// STORAGE ///

    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.

    IMorpho public immutable morpho;
    IPoolAddressesProvider public immutable addressesProvider;
    IPool public immutable pool;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @param _morpho The address of the main Morpho contract.
    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        pool = IPool(morpho.pool());
        addressesProvider = IPoolAddressesProvider(morpho.addressesProvider());
    }
}
