// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IMatchingEngineManager {
    function updateBorrowers(address _poolTokenAddress, address _account) external;

    function updateSuppliers(address _poolTokenAddress, address _account) external;
}
