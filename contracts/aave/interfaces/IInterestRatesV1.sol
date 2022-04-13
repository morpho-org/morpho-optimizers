// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./IInterestRates.sol";

interface IInterestRatesV1 is IInterestRates {
    function supplyWeight(address) external returns (uint256);

    function borrowWeight(address) external returns (uint256);

    function setWeights(
        address,
        uint256,
        uint256
    ) external;
}
