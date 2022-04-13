// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IMarketsManagerForAave {
    function isCreated(address _marketAddress) external returns (bool);

    function noP2P(address _marketAddress) external view returns (bool);

    function supplyP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function borrowP2PExchangeRate(address _marketAddress) external view returns (uint256);

    function exchangeRatesLastUpdateTimestamp(address _marketAddress) external returns (uint256);

    function updateP2PExchangeRates(address _marketAddress) external;

    function getUpdatedP2PExchangeRates(address _marketAddress)
        external
        view
        returns (uint256, uint256);
}
