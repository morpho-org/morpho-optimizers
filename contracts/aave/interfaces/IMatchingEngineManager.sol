// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./IPositionsManagerForAaveStorage.sol";

interface IMatchingEngineManager is IPositionsManagerForAaveStorage {
    function updateBorrowers(address _poolTokenAddress, address _account) external;

    function updateSuppliers(address _poolTokenAddress, address _account) external;
}
