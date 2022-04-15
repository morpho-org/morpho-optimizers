// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestInterestRates is TestSetup {
    function testExchangeRateComputation() public {
        Types.Params memory params = Types.Params(
            1 * WAD, // supplyP2PExchangeRate;
            1 * WAD, // borrowP2PExchangeRate
            2 * WAD, // poolSupplyExchangeRate;
            3 * WAD, // poolBorrowExchangeRate;
            1 * WAD, // lastPoolSupplyExchangeRate;
            1 * WAD, // lastPoolBorrowExchangeRate;
            0, // reserveFactor;
            Types.Delta(0, 0, 0, 0) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertEq(newSupplyP2PExchangeRate, (7 * WAD) / 3);
        assertEq(newBorrowP2PExchangeRate, (7 * WAD) / 3);
    }

    function testExchangeRateComputationWithReserveFactor() public {
        Types.Params memory params = Types.Params(
            1 * WAD, // supplyP2PExchangeRate;
            1 * WAD, // borrowP2PExchangeRate
            2 * WAD, // poolSupplyExchangeRate;
            3 * WAD, // poolBorrowExchangeRate;
            1 * WAD, // lastPoolSupplyExchangeRate;
            1 * WAD, // lastPoolBorrowExchangeRate;
            5_000, // reserveFactor;
            Types.Delta(0, 0, 0, 0) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertEq(newSupplyP2PExchangeRate, ((2 * 2 + 1 * 3) * WAD) / 3 / 2 + (2 * WAD) / 2);
        assertEq(newBorrowP2PExchangeRate, ((2 * 2 + 1 * 3) * WAD) / 3 / 2 + (3 * WAD) / 2);
    }

    function testExchangeRateComputationWithDelta() public {
        Types.Params memory params = Types.Params(
            1 * WAD, // supplyP2PExchangeRate;
            1 * WAD, // borrowP2PExchangeRate
            2 * WAD, // poolSupplyExchangeRate;
            3 * WAD, // poolBorrowExchangeRate;
            1 * WAD, // lastPoolSupplyExchangeRate;
            1 * WAD, // lastPoolBorrowExchangeRate;
            0, // reserveFactor;
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        console.log(newSupplyP2PExchangeRate);
        console.log(newBorrowP2PExchangeRate);

        assertEq(newSupplyP2PExchangeRate, ((7 * WAD) / 3 + 2 * WAD) / 2);
        assertEq(newBorrowP2PExchangeRate, ((7 * WAD) / 3 + 3 * WAD) / 2);
    }

    function testExchangeRateComputationWithDeltaAndReserveFactor() public {
        Types.Params memory params = Types.Params(
            1 * WAD, // supplyP2PExchangeRate;
            1 * WAD, // borrowP2PExchangeRate
            2 * WAD, // poolSupplyExchangeRate;
            3 * WAD, // poolBorrowExchangeRate;
            1 * WAD, // lastPoolSupplyExchangeRate;
            1 * WAD, // lastPoolBorrowExchangeRate;
            5_000, // reserveFactor;
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertEq(newSupplyP2PExchangeRate, (((7 * WAD) / 3 + 2 * WAD) / 2 + 2 * WAD) / 2);
        assertEq(newBorrowP2PExchangeRate, (((7 * WAD) / 3 + 3 * WAD) / 2 + 3 * WAD) / 2);
    }
}
