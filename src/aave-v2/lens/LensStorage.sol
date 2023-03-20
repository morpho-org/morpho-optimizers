// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "../interfaces/aave/IPriceOracleGetter.sol";
import "../interfaces/aave/ILendingPool.sol";
import "../interfaces/aave/IAToken.sol";
import "../interfaces/IMorpho.sol";
import "./interfaces/ILens.sol";

import "../libraries/aave/DataTypes.sol";
import "../libraries/InterestRatesModel.sol";
import "../libraries/aave/ReserveConfiguration.sol";
import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage is ILens {
    /// CONSTANTS ///

    uint16 public constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 50_00; // 50% in basis points.
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // Health factor below which the positions can be liquidated.

    address public constant ST_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// IMMUTABLES ///

    // stETH is a rebasing token, so the rebase index's value when the astEth market was created is stored
    // and used for internal calculations to convert `stEth.balanceOf` into an amount in pool supply unit.
    uint256 public immutable ST_ETH_BASE_REBASE_INDEX;

    IMorpho public immutable morpho;
    ILendingPoolAddressesProvider public immutable addressesProvider;
    ILendingPool public immutable pool;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @param _morpho The address of the main Morpho contract.
    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        pool = ILendingPool(morpho.pool());
        addressesProvider = ILendingPoolAddressesProvider(morpho.addressesProvider());
        ST_ETH_BASE_REBASE_INDEX = morpho.ST_ETH_BASE_REBASE_INDEX();
    }
}
