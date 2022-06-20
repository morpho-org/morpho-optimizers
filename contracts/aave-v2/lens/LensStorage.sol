// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "../interfaces/aave/IPriceOracleGetter.sol";
import "../interfaces/aave/ILendingPool.sol";
import "../interfaces/aave/IAToken.sol";
import "../interfaces/IMorpho.sol";

import "../libraries/aave/ReserveConfiguration.sol";
import "../libraries/aave/PercentageMath.sol";
import "../libraries/aave/WadRayMath.sol";
import "../libraries/aave/DataTypes.sol";
import "../libraries/InterestRatesModel.sol";
import "../libraries/Math.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage is Initializable {
    /// STORAGE ///

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis points).
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.
    uint256 public constant RAY = 1e27;

    IMorpho public morpho;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public pool;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}
}
