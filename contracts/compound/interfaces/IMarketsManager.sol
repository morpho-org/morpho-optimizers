// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IMarketsManager {
    function isCreated(address _poolTokenAddress) external returns (bool);

    function noP2P(address _poolTokenAddress) external view returns (bool);

    function supplyP2PIndex(address _poolTokenAddress) external view returns (uint256);

    function borrowP2PIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedSupplyP2PIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedBorrowP2PIndex(address _poolTokenAddress) external view returns (uint256);

    function lastUpdateBlockNumber(address _poolTokenAddress) external view returns (uint256);

    function updateP2PIndexes(address _marketAddress) external;

    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        returns (uint256, uint256);
}
