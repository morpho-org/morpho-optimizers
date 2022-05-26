// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestGasConsumption is TestSetup {
    // Hyper parameters to get the gas estimate for
    uint256 public maxSortedUsers = 50;
    uint256 public numberOfMatches = 25;

    // Give you the cost of a loop (MatchBorrowers)
    function testGasConsumptionOfMatchBorrowers() external {
        morpho.setMaxSortedUsers(maxSortedUsers);
        createSigners(maxSortedUsers + numberOfMatches + 1);

        // 1: Create maxSortedUsers matches on DAI market to fill the FIFO
        uint256 matchedAmount = (maxSortedUsers * 1000 ether);
        for (uint256 i; i < maxSortedUsers; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(cDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(cUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(cDai, matchedAmount);
        }

        uint256 amount = matchedAmount / 10;
        uint256 collateral = 2 * amount;

        // 2: There are numberOfMatches borrowers waiting on Pool.
        for (uint256 i = maxSortedUsers; i < numberOfMatches + maxSortedUsers; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, amount / numberOfMatches);
        }

        // Must supply more than borrowed by borrowers[maxSortedUsers] to trigger the supply on pool mechanism
        suppliers[numberOfMatches + maxSortedUsers].approve(dai, 2 * amount);
        suppliers[numberOfMatches + maxSortedUsers].supply(cDai, 2 * amount, type(uint256).max);
    }
}
