// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./IPositionsManagerForCompound.sol";

interface IMarketsManagerForCompound {
    function isCreated(address) external view returns (bool);

    function p2pBPY(address) external view returns (uint256);

    function p2pExchangeRate(address) external view returns (uint256);

    function lastUpdateBlockNumber(address) external view returns (uint256);

    function setPositionsManager(address _positionsManagerForCompound) external;

    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external;

    function createMarket(address _marketAddress, uint256 _threshold) external;

    function updateThreshold(address _marketAddress, uint256 _newThreshold) external;

    function updateRates(address _marketAddress) external;
}