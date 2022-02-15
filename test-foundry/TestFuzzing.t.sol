pragma solidity 0.8.7;

import "./utils/TestSetup.sol";
import "hardhat/console.sol";

contract TestSupply is TestSetup {
    function test_supply_fuzzing(
        uint128 _amount,
        uint16 _reserveFactor,
        uint8 _nbOfMarkets,
        uint8 _nbOfOthersUsers,
        uint8 _timeElapsed
    ) public {
        // Create signers & Alice
        User Alice = (new User(positionsManager, marketsManager, rewardsManager));
        fillBalances(address(Alice));
        createSigners(_nbOfOthersUsers);

        // Set reserve factor
        _reserveFactor = uint16(_reserveFactor % MAX_BASIS_POINTS);
        marketsManager.setReserveFactor(_reserveFactor);

        // Get amount of Markets entered by the user
        _nbOfMarkets = uint8(_nbOfMarkets % pools.length);

        Asset memory supply;
        Asset memory borrow;
        uint256 proportion;
        uint256 maxToBorrow;
        uint256 randomlySupplied;

        // Loop for each entered market
        for (uint8 j = 0; j < _nbOfMarkets; j++) {
            // Get supply asset of the user
            (supply, borrow) = getAssets(_amount, j, uint8((2 * j) % pools.length));

            for (uint256 i = 0; i < _nbOfOthersUsers; i++) {
                proportion = getBasisPoints(address(suppliers[i]));
                suppliers[i].supply(
                    supply.poolToken,
                    (supply.amount * proportion * 2) / MAX_BASIS_POINTS
                );

                // get a new random proportion for borrower
                // `* 2` because those users might borrow/supply more than Alice
                proportion = getBasisPoints(address(suppliers[i]));
                randomlySupplied = (supply.amount * proportion * 2) / MAX_BASIS_POINTS;
                borrowers[i].supply(supply.poolToken, randomlySupplied);

                proportion = getBasisPoints(address(borrowers[i]));
                maxToBorrow = getMaxToBorrow(
                    randomlySupplied,
                    supply.underlying,
                    supply.underlying
                );
                borrowers[i].borrow(
                    supply.poolToken,
                    (proportion * maxToBorrow) / MAX_BASIS_POINTS
                );
            }
            Alice.supply(supply.poolToken, supply.amount);
        }
        hevm.warp(block.timestamp + _timeElapsed);
        //TODO: Check that Alice's balance is correct on every market
    }
}
