// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IDataUpdator {
    function updateBorrowerList(address _poolTokenAddress, address _account) external;

    function updateSupplierList(address _poolTokenAddress, address _account) external;
}
