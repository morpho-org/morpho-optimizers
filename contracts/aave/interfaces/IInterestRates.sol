// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./ITypesForAave.sol";

interface IInterestRates is ITypesForAave {
    function computeP2PExchangeRate(Params memory _params)
        external
        pure
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate);

    function computeRates(
        uint256 _poolSupplyRate,
        uint256 _poolBorrowRate,
        uint256 _reserveFactor
    ) external pure returns (uint256 p2pSupplyRate, uint256 p2pBorrowRate);
}
