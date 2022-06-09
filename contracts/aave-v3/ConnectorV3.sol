// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "./interfaces/IConnector.sol";

import "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

contract ConnectorV3 is IConnector {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IPoolAddressesProvider public addressesProvider;
    IPool public immutable pool;

    constructor(address _addressesProvider) {
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
        pool = IPool(addressesProvider.getPool());
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
        return addressesProvider.getPriceOracleSentinel();
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
            ,

        ) = pool.getConfiguration(_underlyingAddress).getParams();
    }
}
