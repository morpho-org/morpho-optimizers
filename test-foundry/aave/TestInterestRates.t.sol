// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestInterestRates is TestSetup {
    function testShouldReturnZero() public {
        (uint256 supplyRate, uint256 borrowRate) = interestRates.computeApproxRates(0, 0, 0);
        assertEq(supplyRate, 0);
        assertEq(borrowRate, 0);
    }

    function testShouldReturnSameRatesIfSameRatesAsInputAndNoReserveFactor() public {
        (uint256 supplyRate, uint256 borrowRate) = interestRates.computeApproxRates(100, 100, 0);
        assertEq(supplyRate, 100);
        assertEq(borrowRate, 100);
    }

    function testShouldReturnTheRightQuantities() public {
        (uint256 supplyRate, uint256 borrowRate) = interestRates.computeApproxRates(0, 100, 0);

        assertEq(supplyRate, 33);
        assertEq(supplyRate, borrowRate);
    }

    function testShouldReturnPoolRatesWhen100PercentReserveFactor() public {
        (uint256 supplyRate, uint256 borrowRate) = interestRates.computeApproxRates(20, 80, 10_000);

        assertEq(supplyRate, 20);
        assertEq(borrowRate, 80);
    }
}
