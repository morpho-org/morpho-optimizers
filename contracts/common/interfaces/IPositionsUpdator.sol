// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IPositionsUpdator {
    function updateBorrowerPositions(address _poolTokenAddress, address _account) external;

    function updateSupplierPositions(address _poolTokenAddress, address _account) external;

    function getBorrowerAccountOnPool(address _poolTokenAddress) external returns (address);

    function getBorrowerAccountInP2P(address _poolTokenAddress) external returns (address);

    function getSupplierAccountOnPool(address _poolTokenAddress) external returns (address);

    function getSupplierAccountInP2P(address _poolTokenAddress) external returns (address);
}
