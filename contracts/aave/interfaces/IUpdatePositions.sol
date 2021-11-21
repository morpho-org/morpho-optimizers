// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IUpdatePositions {
    function updateBorrowerList(address _aTokenAddress, address _account) external;

    function updateSupplierList(address _aTokenAddress, address _account) external;
}
