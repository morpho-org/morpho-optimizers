// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IInterestRatesManager {
    function getUpdatedP2PSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedP2PBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function updateP2PIndexes(address _marketAddress) external;
}
