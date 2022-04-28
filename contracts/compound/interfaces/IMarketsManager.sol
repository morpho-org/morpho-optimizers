// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IMarketsManager {
    function getUpdatedp2pSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedp2pBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function updateP2PIndexes(address _marketAddress) external;

    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        returns (uint256, uint256);
}
