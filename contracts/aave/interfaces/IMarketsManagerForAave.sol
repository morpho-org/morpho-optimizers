// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IMarketsManagerForAave {
    function owner() external returns (address);

    function isCreated(address _marketAddress) external returns (bool);

    function noP2P(address _marketAddress) external view returns (bool);

    function supplyP2PSPY(address _marketAddress) external returns (uint256);

    function borrowP2PSPY(address _marketAddress) external returns (uint256);

    function liquidationIncentive(address _marketAddress) external returns (uint256);

    function supplyP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function borrowP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function lastUpdateBlockNumber(address _marketAddress) external returns (uint256);

    function updateRates(address _marketAddress) external;
}
