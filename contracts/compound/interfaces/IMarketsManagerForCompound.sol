// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IMarketsManagerForCompound {
    function isCreated(address _marketAddress) external returns (bool);

    function p2pBPY(address _marketAddress) external returns (uint256);

    function collateralFactor(address _marketAddress) external returns (uint256);

    function liquidationIncentive(address _marketAddress) external returns (uint256);

    function p2pUnitExchangeRate(address _marketAddress) external returns (uint256);

    function lastUpdateBlockNumber(address _marketAddress) external returns (uint256);

    function threshold(address _marketAddress) external returns (uint256);

    function updateP2pUnitExchangeRate(address _marketAddress) external returns (uint256);
}
