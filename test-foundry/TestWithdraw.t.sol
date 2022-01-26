// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";
import "./utils/Attacker.sol";

contract TestWithdraw is TestSetup {
    // 3.1 - The user withdrawal leads to an under-collateralized position, the withdrawal reverts.
    function test_withdraw_3_1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        borrower1.borrow(aDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.withdraw(aUsdc, to6Decimals(collateral));
    }

    // 3.2 - The supplier withdraws less than his onPool balance. The liquidity is taken from his onPool balance.
    function test_withdraw_3_2() public {
        uint256 amount = 10000 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(aUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );

        uint256 expectedOnPool = to6Decimals(
            underlyingToScaledBalance(2 * amount, lendingPool.getReserveNormalizedIncome(usdc))
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool / 2);
    }

    // 3.2 BIS - withdraw all
    function test_withdraw_3_2_BIS() public {
        uint256 amount = 10000 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        uint256 balanceBefore = supplier1.balanceOf(usdc);
        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );

        uint256 expectedOnPool = to6Decimals(
            underlyingToScaledBalance(amount, lendingPool.getReserveNormalizedIncome(usdc))
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(aUsdc, type(uint256).max);

        uint256 balanceAfter = supplier1.balanceOf(usdc);
        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
        testEquality(balanceAfter - balanceBefore, to6Decimals(amount));
    }

    // 3.3 - The supplier withdraws more than his onPool balance

    // 3.3.1 - There is a supplier onPool available to replace him inP2P.
    // First, his liquidity onPool is taken, his matched is replaced by the available supplier up to his withdrawal amount.
    function test_withdraw_3_3_1() public {
        uint256 borrowedAmount = 10000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(aDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier2)
        );
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedInP2P = underlyingToP2PUnit(suppliedAmount / 2, supplyP2PExchangeRate);
        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(inP2PSupplier, expectedInP2P);

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PSupplier, inP2PBorrower1);
    }

    // 3.3.2 - There are NMAX (or less) suppliers onPool available to replace him inP2P, they supply enough to cover for the withdrawn liquidity.
    // First, his liquidity onPool is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
    function test_withdraw_3_3_2() public {
        uint256 borrowedAmount = 100000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (NMAX - 1);
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount,
            supplyP2PExchangeRate
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, 0);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }
    }

    // 3.3.3 - There are no suppliers onPool to replace him inP2P. After withdrawing the amount onPool,
    // his P2P match(es) will be unmatched and the corresponding borrower(s) will be placed on pool.
    function test_withdraw_3_3_3() public {
        uint256 borrowedAmount = 10000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // Supplier1 withdraws 75% of supplied amount
        supplier1.withdraw(aDai, (75 * suppliedAmount) / 100);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount / 2,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowedAmount / 2,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            (25 * suppliedAmount) / 100,
            supplyP2PExchangeRate
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, 0);
    }

    // 3.3.4 - The supplier is matched to 2*NMAX borrowers. There are NMAX suppliers `onPool` available to replace him `inP2P`,
    //         they don't supply enough to cover the withdrawn liquidity.
    //         First, the `onPool` liquidity is withdrawn, then we proceed to NMAX `match supplier`.
    //         Finally, we proceed to NMAX `unmatch borrower` for an amount equal to the remaining to withdraw.
    //         ⚠️ most gas expensive withdraw scenario.
    function test_withdraw_3_3_4() public {
        uint256 borrowedAmount = 100000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (NMAX - 1));
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount / 2,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowedAmount / 2,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            testEquality(inP2P, 0);
        }
    }

    // Delta hard withdraw
    function test_withdraw_3_3_5() public {
        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount;

        // supplier1 and 100 borrowers are matched for suppliedAmount
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        positionsManager.setNmaxForMatchingEngine(10);
        createSigners(30);

        // 2 * NMAX borrowers borrow borrowedAmount
        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, borrowedAmount);
        }

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            suppliedAmount,
            supplyP2PExchangeRate
        );

        // Check balances after match of supplier1 and borrowers
        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount,
            borrowP2PExchangeRate
        );

        for (uint256 i = 0; i < 20; i++) {
            (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
                aDai,
                address(borrowers[i])
            );
            testEquality(onPoolBorrower, 0);
            testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        }

        // supplier withdraws max
        // should create a delta on borrowers side
        supplier1.withdraw(aDai, type(uint256).max);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // There should be a delta
        uint256 expectedBorrowP2PDelta = 10 * borrowedAmount;
        testEquality(positionsManager.borrowP2PDelta(aDai), expectedBorrowP2PDelta);

        // Delta matching
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(aDai, suppliedAmount);

        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier2)
        );
        expectedSupplyBalanceInP2P = underlyingToP2PUnit(suppliedAmount, supplyP2PExchangeRate);

        testEquality(positionsManager.borrowP2PDelta(aDai), 0);
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
    }

    // Test attack
    // Should not be possible to withdraw amount if the position turns to be under-collateralized
    function test_withdraw_if_under_collaterize() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = toSupply / 2;

        // supplier1 deposits collateral
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        // supplier2 deposits collateral
        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        // supplier1 tries to withdraw more than allowed
        supplier1.borrow(aUsdc, to6Decimals(toBorrow));
        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        supplier1.withdraw(aDai, toSupply);
    }

    // Test attack
    // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    function test_withdraw_while_attacker_sends_AToken() public {
        Attacker attacker = new Attacker(lendingPool);
        writeBalanceOf(address(attacker), dai, type(uint256).max / 2);

        uint256 toSupply = 100 ether;
        uint256 collateral = 2 * toSupply;
        uint256 toBorrow = toSupply;

        // attacker sends aToken to positionsManager contract
        attacker.approve(dai, address(lendingPool), toSupply);
        attacker.deposit(dai, toSupply, address(attacker), 0);
        attacker.transfer(dai, address(positionsManager), toSupply);

        // supplier1 deposits collateral
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        // borrower1 deposits collateral
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        // supplier1 tries to withdraw
        borrower1.borrow(aDai, toBorrow);
        supplier1.withdraw(aDai, toSupply);
    }
}
