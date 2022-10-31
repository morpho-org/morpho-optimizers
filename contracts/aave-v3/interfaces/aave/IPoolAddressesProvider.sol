// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.5.0;

interface IPoolAddressesProvider {
    function getPool() external view returns (address);

    function getPriceOracle() external view returns (address);

    function getPriceOracleSentinel() external view returns (address);

    function owner() external view returns (address);

    function getPoolConfigurator() external view returns (address);
}
