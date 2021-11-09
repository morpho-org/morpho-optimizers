// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IMarketsManagerForCompLike {
    function isCreated(address _marketAddress) external returns (bool);

    function p2pBPY(address _marketAddress) external returns (uint256);

    function collateralFactor(address _marketAddress) external returns (uint256);

    function liquidationIncentive(address _marketAddress) external returns (uint256);

    function mUnitExchangeRate(address _marketAddress) external returns (uint256);

    function lastUpdateBlockNumber(address _marketAddress) external returns (uint256);

    function thresholds(address _marketAddress) external returns (uint256);

    function updateMUnitExchangeRate(address _marketAddress) external returns (uint256);

    function assets(uint256 assetIndex) external view returns (address);

    function getAssetsLength() external view returns (uint256);

    function assetIndexes(address asset) external view returns (uint256);
}
