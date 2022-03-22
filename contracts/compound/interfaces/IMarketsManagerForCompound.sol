// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IMarketsManagerForCompound {
    function isCreated(address _poolTokenAddress) external returns (bool);

    function noP2P(address _poolTokenAddress) external view returns (bool);

    function supplyP2PBPY(address _poolTokenAddress) external returns (uint256);

    function borrowP2PBPY(address _poolTokenAddress) external returns (uint256);

    function supplyP2PExchangeRate(address _poolTokenAddress) external view returns (uint256);

    function borrowP2PExchangeRate(address _poolTokenAddress) external view returns (uint256);

    function lastUpdateBlockNumber(address _poolTokenAddress) external view returns (uint256);

    function updateRates(address _poolTokenAddress) external;

    function updateP2PExchangeRates(address _marketAddress) external;

    function updateBPYs(address _poolTokenAddress) external;

    function getUpdatedSupplyP2PExchangeRate(address _poolTokenAddress)
        external
        view
        returns (uint256);

    function getUpdatedBorrowP2PExchangeRate(address _poolTokenAddress)
        external
        view
        returns (uint256);
}
