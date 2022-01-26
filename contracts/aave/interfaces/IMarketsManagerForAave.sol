// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./dependencies/@openzeppelin/IOwnable.sol";

interface IMarketsManagerForAave is IOwnable {
    function MAX_BASIS_POINTS() external view returns (uint256);

    function SECONDS_PER_YEAR() external view returns (uint256);

    function reserveFactor() external view returns (uint256);

    function isCreated(address) external view returns (bool);

    function supplyP2PSPY(address) external view returns (uint256);

    function borrowP2PSPY(address) external view returns (uint256);

    function supplyP2PExchangeRate(address) external view returns (uint256);

    function borrowP2PExchangeRate(address) external view returns (uint256);

    function exchangeRatesLastUpdateTimestamp(address) external view returns (uint256);

    function noP2P(address) external view returns (bool);

    function setPositionsManager(address _positionsManagerForAave) external;

    function updateLendingPool() external;

    function setReserveFactor(uint256 _newReserveFactor) external;

    function createMarket(
        address _marketAddress,
        uint256 _threshold,
        uint256 _capValue
    ) external;

    function setThreshold(address _marketAddress, uint256 _newThreshold) external;

    function setCapValue(address _marketAddress, uint256 _newCapValue) external;

    function setNoP2P(address _marketAddress, bool _noP2P) external;

    function updateRates(address _marketAddress) external;
}
