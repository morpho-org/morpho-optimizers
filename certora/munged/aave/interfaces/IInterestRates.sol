// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/Types.sol";

interface IInterestRates {
    function computeP2PExchangeRates(Types.Params memory _params)
        external
        pure
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate);
}
