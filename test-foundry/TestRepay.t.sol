// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestRepay is TestSetup {
    // - 4.1 - The borrower repays less than his `onPool` balance. The liquidity is repaid on his `onPool` balance.
    function test_repay_4_1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        borrower1.approve(dai, amount);
        borrower1.repay(aDai, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
    }

    // - 4.1 BIS - repay all
    function test_repay_4_1_BIS() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        uint256 balanceBefore = borrower1.balanceOf(dai);
        borrower1.approve(dai, amount);
        borrower1.repay(aDai, type(uint256).max);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        uint256 balanceAfter = supplier1.balanceOf(dai);

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
        testEquality(balanceBefore - balanceAfter, amount);
    }

    // - 4.2 - The borrower repays more than his `onPool` balance.
    //   - 4.2.1 - There is a borrower `onPool` available to replace him `inP2P`.
    //             First, his debt `onPool` is repaid, his matched debt is replaced by the available borrower up to his repaid amount.
    function test_repay_4_2_1() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            suppliedAmount,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // An available borrower onPool
        uint256 availableBorrowerAmount = borrowedAmount / 4;
        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(aUsdc, to6Decimals(collateral));
        borrower2.borrow(aDai, availableBorrowerAmount);

        // Borrower1 repays 75% of suppliedAmount
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(aDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower1 & borrower2
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PAvailableBorrower, uint256 onPoolAvailableBorrower) = positionsManager
        .borrowBalanceInOf(aDai, address(borrower2));
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            (25 * borrowedAmount) / 100,
            borrowP2PExchangeRate
        );

        testEquality(inP2PBorrower1, inP2PAvailableBorrower);
        testEquality(inP2PBorrower1, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower1, 0);
        testEquality(onPoolAvailableBorrower, 0);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(2 * inP2PBorrower1, inP2PSupplier);
        testEquality(onPoolSupplier, 0);
    }

    //   - 4.2.2 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they borrow enough to cover for the repaid liquidity.
    //             First, his debt `onPool` is repaid, his matched liquidity is replaced by NMAX (or less) borrowers up to his repaid amount.
    function test_repay_4_2_2() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched up to suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            suppliedAmount,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have debt waiting on pool
        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 inP2P;
        uint256 onPool;
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);

        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (NMAX - 1);
        // minus because borrower1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            expectedOnPool = underlyingToAdUnit(amountPerBorrower, normalizedVariableDebt);

            testEquality(inP2P, 0);
            testEquality(onPool, expectedOnPool);
        }

        // Borrower1 repays all of his debt
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(aDai, borrowedAmount);

        // His balance should be set to 0
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PBorrower1, 0);

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            suppliedAmount,
            borrowP2PExchangeRate
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, 0);

        // Now test for each individual borrower that replaced the original
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, borrowP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower);
            testEquality(onPool, 0);
        }
    }

    //   - 4.2.3 - There are no borrowers `onPool` to replace him `inP2P`. After repaying the amount `onPool`,
    //             his P2P match(es) will be unmatched and the corresponding supplier(s) will be placed on pool.
    function test_repay_4_2_3() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for supplierAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            suppliedAmount,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // Borrower1 repays 75% of borrowed amount
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(aDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);

        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            (25 * borrowedAmount) / 100,
            borrowP2PExchangeRate
        );

        testEquality(inP2PBorrower1, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower1, 0);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            suppliedAmount / 2,
            borrowP2PExchangeRate
        );
        uint256 expectedSupplyBalanceOnPool = underlyingToAdUnit(
            suppliedAmount / 2,
            normalizedIncome
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool);
    }

    //   4.2.4 - The borrower is matched to 2\*NMAX suppliers. There are NMAX borrowers `onPool` available to replace him `inP2P`,
    //           they don't supply enough to cover for the repaid liquidity. First, the `onPool` liquidity is repaid, then we proceed to NMAX `match borrower`.
    //           Finally, we proceed to NMAX `unmatch supplier` for an amount equal to the remaining to withdraw.
    //           ⚠️ most gas expensive repay scenario.
    function test_repay_4_2_4() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            suppliedAmount,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have borrowerAmount/2 (cumulated) of debt waiting on pool
        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (2 * (NMAX - 1));
        // minus because borrower1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        // Borrower1 repays all of his debt
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(aDai, borrowedAmount);

        // His balance should be set to 0
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PBorrower1, 0);

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);

        uint256 expectedSupplyBalanceOnPool = underlyingToP2PUnit(
            suppliedAmount / 2,
            normalizedIncome
        );
        uint256 expectedSupplyBalanceInP2P = underlyingToAdUnit(
            suppliedAmount / 2,
            borrowP2PExchangeRate
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual borrower that replaced the original
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, borrowP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower);
            testEquality(onPool, 0);
        }
    }

    // Delta hard repay
    function test_repay_4_2_5() public {
        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 20 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // borrower1 and 100 suppliers are matched for borrowedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        positionsManager.setNmaxForMatchingEngine(10);
        createSigners(30);

        // 2 * NMAX suppliers supply suppliedAmount
        for (uint256 i = 0; i < 20; i++) {
            suppliers[i].approve(dai, suppliedAmount);
            suppliers[i].supply(aDai, suppliedAmount);
        }

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount,
            borrowP2PExchangeRate
        );

        // Check balances after match of supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            suppliedAmount,
            supplyP2PExchangeRate
        );

        for (uint256 i = 0; i < 20; i++) {
            (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
                aDai,
                address(suppliers[i])
            );
            testEquality(onPoolSupplier, 0);
            testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        }

        // Borrower repays max
        // Should create a delta on suppliers side
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        // Check balances for borrower1
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PBorrower, 0);

        // There should be a delta
        uint256 expectedSupplyP2PDeltaInUnderlying = 10 * suppliedAmount;
        uint256 expectedSupplyP2PDelta = underlyingToScaledBalance(
            expectedSupplyP2PDeltaInUnderlying,
            lendingPool.getReserveNormalizedIncome(dai)
        );
        testEquality(positionsManager.supplyP2PDelta(aDai), expectedSupplyP2PDelta);

        // Supply delta matching by a new borrower
        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(aUsdc, to6Decimals(collateral));
        borrower2.borrow(aDai, expectedSupplyP2PDeltaInUnderlying / 2);

        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower2)
        );
        expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            expectedSupplyP2PDeltaInUnderlying / 2,
            borrowP2PExchangeRate
        );

        testEquality(positionsManager.supplyP2PDelta(aDai), expectedSupplyP2PDelta / 2);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);

        // Supply delta reduction with suppliers withdrawing
        for (uint256 i = 0; i < 10; i++) {
            suppliers[i].withdraw(aDai, suppliedAmount);
        }

        testEquality(positionsManager.supplyP2PDelta(aDai), 0);
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower2)
        );
        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
    }
}
