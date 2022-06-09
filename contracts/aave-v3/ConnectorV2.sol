// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {ILendingPoolAddressesProvider} from "../aave-v2/interfaces/aave/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "../aave-v2/interfaces/aave/ILendingPool.sol";
import "./interfaces/IConnector.sol";

import "../aave-v2/libraries/aave/ReserveConfiguration.sol";

contract ConnectorV2 is IConnector {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public immutable pool;

    constructor(address _addressesProvider) {
        addressesProvider = ILendingPoolAddressesProvider(_addressesProvider);
        pool = ILendingPool(addressesProvider.getLendingPool());
    }

    function getAddressesProvider() external returns (address) {
        return address(addressesProvider);
    }

    function getPool() external returns (address) {
        return address(pool);
    }

    function getATokenAddress(address _underlyingAddress) external returns (address) {
        return pool.getReserveData(_underlyingAddress).aTokenAddress;
    }

    function getVariableDebtTokenAddress(address _underlyingAddress) external returns (address) {
        return pool.getReserveData(_underlyingAddress).variableDebtTokenAddress;
    }

    function isActive(address _underlyingAddress) external returns (bool) {
        return pool.getConfiguration(_underlyingAddress).getActive();
    }

    function isBorrowingEnabled(address _underlyingAddress) external returns (bool) {
        return pool.getConfiguration(_underlyingAddress).getBorrowingEnabled();
    }

    function getPriceOracleSentinel() external returns (address) {
        return address(0);
    }

    function getConfigurationParams(address _underlyingAddress)
        external
        returns (IConnector.ConfigParams memory config)
    {
        (
            config.ltv,
            config.liquidationThreshold,
            config.liquidationBonus,
            config.reserveDecimals,

        ) = pool.getConfiguration(_underlyingAddress).getParamsMemory();
    }
}
