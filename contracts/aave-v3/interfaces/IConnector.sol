// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

interface IConnector {
    struct ConfigParams {
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 reserveDecimals;
    }

    function getAddressesProvider() external returns (address);

    function getPool() external returns (address);

    function getATokenAddress(address _underlyingAddress) external returns (address);

    function getVariableDebtTokenAddress(address _underlyingAddress) external returns (address);

    function isActive(address _underlyingAddress) external returns (bool);

    function isBorrowingEnabled(address _underlyingAddress) external returns (bool);

    function getPriceOracleSentinel() external returns (address);

    function getConfigurationParams(address _underlyingAddress)
        external
        returns (ConfigParams memory config);
}
