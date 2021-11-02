// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IMarketsManagerForAave {
    function isCreated(address _marketAddress) external returns (bool);

    function p2pSPY(address _marketAddress) external returns (uint256);

    function collateralFactor(address _marketAddress) external returns (uint256);

    function liquidationIncentive(address _marketAddress) external returns (uint256);

    function p2pUnitExchangeRate(address _marketAddress) external returns (uint256);

    function lastUpdateBlockNumber(address _marketAddress) external returns (uint256);

    function thresholds(address _marketAddress) external returns (uint256);

    function updateP2PUnitExchangeRate(address _marketAddress) external returns (uint256);
}
