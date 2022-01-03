// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IPositionsUpdator {
    function updateMaxIterations(uint16 _maxIterations) external;

    function updateBorrowerPositions(address _poolTokenAddress, address _account) external;

    function updateSupplierPositions(address _poolTokenAddress, address _account) external;

    function getValueOf(
        uint8 _positionType,
        address _poolTokenAddress,
        address _account
    ) external returns (uint256);

    function getFirst(uint8 _positionType, address _poolTokenAddress) external returns (address);

    function getLast(uint8 _positionType, address _poolTokenAddress) external returns (address);

    function getNext(
        uint8 _positionType,
        address _poolTokenAddress,
        address _account
    ) external returns (address);

    function getPrev(
        uint8 _positionType,
        address _poolTokenAddress,
        address _account
    ) external returns (address);
}
