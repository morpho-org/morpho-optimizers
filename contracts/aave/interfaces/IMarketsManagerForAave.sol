// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IMarketsManagerForAave {
    function isCreated(address _marketAddress) external returns (bool);

    function noP2P(address _marketAddress) external view returns (bool);

    function supplyP2PSPY(address _marketAddress) external returns (uint256);

    function borrowP2PSPY(address _marketAddress) external returns (uint256);

    function supplyP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function borrowP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function exchangeRatesLastUpdateTimestamp(address _marketAddress) external returns (uint256);

    function updateRates(address _marketAddress) external;

    function updateP2PExchangeRates(address _marketAddress) external;

    function updateSPYs(address _marketAddress) external;
}
