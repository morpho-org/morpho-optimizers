// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestGasConsumption is TestSetup {
    // Hyperparameters to get the gas estimate for
    uint8 public NDS = 50;
    uint8 public numberOfMatches = 25;

    // Give you the cost of a loop (MatchBorrowers)
    function test_updateBorrowers() external {
        positionsManager.setNDS(NDS);
        createSigners(NDS + numberOfMatches + 1);

        // 1: Create NDS matches on DAI market to fill the FIFO
        uint256 matchedAmount = (uint256(NDS) * 1000 ether);
        for (uint8 i = 0; i < NDS; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        uint256 amount = matchedAmount / 10;
        uint256 collateral = 2 * amount;

        // 2: There are numberOfMatches borrowers waiting on Pool.
        for (uint256 i = NDS; i < numberOfMatches + NDS; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amount / numberOfMatches);
        }

        // Must supply more than borrowed by borrowers[NDS] to trigger the supply on pool mechanism
        suppliers[numberOfMatches + NDS].approve(dai, 2 * amount);
        suppliers[numberOfMatches + NDS].supply(aDai, 2 * amount, type(uint256).max);
    }
}
