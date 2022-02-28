// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestGasConsumption is TestSetup {
    uint8 public NDS = 20;

    function test_match_single_supplier() external {
        uint256 amount = 100 ether;
        uint256 collateral = 4 * amount;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        // 1 match supplier
        borrower1.borrow(aDai, amount, type(uint64).max);
    }

    function test_supply_gas_consumption() external {
        positionsManager.setNDS(NDS);
        createSigners(NDS);

        // Create NDS matches on DAI market to fill the FIFO
        uint256 matchedAmount = (uint256(NDS) * 1000 ether);
        for (uint8 i = 0; i < NDS; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        uint256 amount = 100 ether;
        uint256 collateral = 4 * amount;

        // borrower1 waiting on pool
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount / 2);

        supplier1.approve(dai, 2 * amount);

        // 0 match
        supplier1.supply(aDai, amount, 0);

        // 1 match
        // Must supply more than borrowed by borrower1 to trigger the supply on pool mechanism
        supplier1.supply(aDai, amount, type(uint64).max);

        // The difference gives us the cost of one loop (with insertion in NDS steps) and the cost of the logic.
    }

    function test_borrow_gas_consumption() external {
        positionsManager.setNDS(NDS);
        createSigners(NDS);

        // Create NDS matches on DAI market to fill the FIFO
        uint256 matchedAmount = (uint256(NDS) * 1000 ether);
        for (uint8 i = 0; i < NDS; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        uint256 amount = 100 ether;
        uint256 collateral = 8 * amount;

        // supplier1 waiting on pool
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        // 0 match
        borrower1.borrow(aDai, 2 * amount, 0);

        // 1 match
        // Must borrow more than supplied by supplier1 to trigger the borrow on pool mechanism
        borrower1.borrow(aDai, 2 * amount, type(uint64).max);
    }

    function test_withdraw_gas_consumption() external {
        positionsManager.setNDS(NDS);
        createSigners(NDS);

        uint256 amount = 100 ether;
        uint256 collateral = 4 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount, type(uint64).max);

        supplier2.approve(dai, amount);
        supplier2.supply(aDai, amount, type(uint64).max);

        // 1 match suppliers
        // 0 unmatch borrowers
        supplier1.withdraw(aDai, amount);

        // borrower1 and supplier2 are matched for amount

        // Create NDS matches on DAI market to fill the FIFO
        uint256 matchedAmount = (uint256(NDS) * 1000 ether);
        for (uint8 i = 0; i < NDS; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // supplier2 supplies another amount
        supplier2.approve(dai, amount);
        supplier2.supply(aDai, amount, type(uint64).max);

        // borrower1 is matched with supplier2 for 2 * amount
        borrower1.borrow(aDai, amount, type(uint64).max);

        // supplier1 is waiting on pool
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount, type(uint64).max);

        // 1 match suppliers
        // 1 unmatch borrowers
        supplier2.withdraw(aDai, 2 * amount);
    }

    function test_repay_gas_consumption() external {
        positionsManager.setNDS(NDS);
        createSigners(NDS);

        uint256 amount = 100 ether;
        uint256 collateral = 4 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount, type(uint64).max);

        // supplier1 and borrower1 are matched with amount

        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(aUsdc, to6Decimals(collateral));
        borrower2.borrow(aDai, amount);

        // 1 match borrowers
        // 0 unmatch suppliers
        borrower1.approve(dai, amount);
        borrower1.repay(aDai, amount);

        // supplier1 and borrower2 are matched with amount

        // Create NDS matches on DAI market to fill the FIFO
        uint256 matchedAmount = (uint256(NDS) * 1000 ether);
        for (uint8 i = 0; i < NDS; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // borrower2 borrowers another amount
        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(aUsdc, to6Decimals(collateral));
        borrower2.borrow(aDai, amount);

        // supplier1 is matched with borrower2 for 2 * amount
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount, type(uint64).max);

        // borrower1 is waiting on pool
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        // 1 match borrowers
        // 1 unmatch suppliers
        borrower2.approve(dai, 2 * amount);
        borrower2.repay(aDai, 2 * amount);
    }

    function test_liquidate_gas_consumption() public {
        uint256 collateral = 100_000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        (, uint256 amount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, (amount * 4) / 5); // For on pool + in P2P
        // nothing // For on pool
        // supplier1.supply(aDai, amount); // For in P2P

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getAssetPrice(usdc) * 93) / 100);

        // Liquidate
        uint256 toRepay = (amount * 999) / 2000;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);
    }
}
