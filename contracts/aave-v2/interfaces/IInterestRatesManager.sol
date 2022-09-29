// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

interface IInterestRatesManager {
    function ST_ETH() external view returns (address);

    function ST_ETH_BASE_REBASE_INDEX() external view returns (uint256);

    function updateIndexes(address _marketAddress) external;

    function getUpdatedIndexes(address _poolToken)
        external
        view
        returns (
            uint256 poolSupplyIndex_,
            uint256 poolBorrowIndex_,
            uint256 p2pSupplyIndex_,
            uint256 p2pBorrowIndex_
        );

    function getUpdatedPoolIndexes(address _poolToken)
        external
        view
        returns (uint256 poolSupplyIndex_, uint256 poolBorrowIndex_);

    function getUpdatedP2PIndexes(address _poolToken)
        external
        view
        returns (uint256 p2pSupplyIndex_, uint256 p2pBorrowIndex_);
}
