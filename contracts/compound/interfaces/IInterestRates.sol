// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

interface IInterestRates {
    function computeRates(
        uint256 _poolSupplyRate,
        uint256 _poolBorrowRate,
        uint256 _reserveFactor
    ) external pure returns (uint256 p2pSupplyRate, uint256 p2pBorrowRate);
}
