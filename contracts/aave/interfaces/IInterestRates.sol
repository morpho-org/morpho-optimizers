// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../libraries/Types.sol";

interface IInterestRates {
    function createMarket(address _marketAddress) external;

    function computeP2PExchangeRates(Types.Params memory _params)
        external
        view
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate);
}
