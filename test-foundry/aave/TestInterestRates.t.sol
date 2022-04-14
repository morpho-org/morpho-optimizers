// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestInterestRates is TestSetup {
    function testExchangeRateComputation() public {
        Types.Params memory params = Types.Params(
            1 * RAY, // supplyP2PExchangeRate;
            1 * RAY, // borrowP2PExchangeRate
            2 * RAY, // poolSupplyExchangeRate;
            3 * RAY, // poolBorrowExchangeRate;
            1 * RAY, // lastPoolSupplyExchangeRate;
            1 * RAY, // lastPoolBorrowExchangeRate;
            0, // reserveFactor;
            Types.Delta(0, 0, 0, 0) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertEq(newSupplyP2PExchangeRate, (7 * RAY) / 3);
        assertEq(newBorrowP2PExchangeRate, (7 * RAY) / 3);
    }
}
