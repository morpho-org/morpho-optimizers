// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestRepay is TestSetup {
    // - 4.1 - The borrower repays less than his `onPool` balance. The liquidity is repaid on his `onPool` balance.
    function test_repay_4_1(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.supply(supply.poolToken, supply.amount + 1);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        borrower1.repay(borrow.poolToken, borrow.amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        assertEq(inP2P, 0, "borrower1 in P2P");
        assertEq(onPool, 0, "borrower1 on pool");
    }

    // - 4.2 - The borrower repays more than his `onPool` balance.
    //   - 4.2.1 - There is a borrower `onPool` available to replace him `inP2P`.
    //             First, his debt `onPool` is repaid, his matched debt is replaced by the available borrower up to his repaid amount.
    function test_repay_4_2_1() public {
        (Asset memory supply, Asset memory borrow) = getAssets(10_000 ether, 1, 0);

        // Borrower1 & supplier1 are matched for borrow.amount
        borrower1.supply(supply.poolToken, 2 * supply.amount);
        borrower1.borrow(borrow.poolToken, 2 * borrow.amount);

        supplier1.supply(borrow.poolToken, borrow.amount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            borrow.amount,
            lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
        );

        assertEq(onPoolSupplier, 0, "supplier1 on pool");
        assertEq(onPoolBorrower1, expectedOnPool, "borrower1 on pool");
        assertEq(inP2PSupplier, inP2PBorrower1, "borrower1 / supplier1 in P2P");

        // An available borrower onPool
        borrower2.supply(supply.poolToken, supply.amount);
        borrower2.borrow(borrow.poolToken, borrow.amount / 2);

        // Borrower1 repays 75% of suppliedAmount
        borrower1.repay(borrow.poolToken, (borrow.amount * 2 * 75) / 100);

        // Check balances for borrower1 & borrower2
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PBorrower2, uint256 onPoolBorrower2) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower2)
        );
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            (borrow.amount * 2 * 25) / 100,
            marketsManager.borrowP2PExchangeRate(borrow.poolToken)
        );

        assertApproxEq(
            inP2PBorrower1,
            expectedBorrowBalanceInP2P,
            1,
            "borrower1 in P2P after repay"
        );
        assertEq(onPoolBorrower1, 0, "borrower1 on pool after repay");
        assertApproxEq(inP2PBorrower2, inP2PBorrower1, 1, "borrower2/borrower1 in P2P");
        assertEq(onPoolBorrower2, 0, "borrower2 on pool");

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );
        assertApproxEq(inP2PSupplier, 2 * inP2PBorrower1, 1, "supplier1 in P2P after repay");
        assertApproxEq(onPoolSupplier, 0, 1, "supplier1 on pool after repay");
    }

    //   - 4.2.2 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they borrow enough to cover for the repaid liquidity.
    //             First, his debt `onPool` is repaid, his matched liquidity is replaced by NMAX (or less) borrowers up to his repaid amount.
    function test_repay_4_2_2() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched up to suppliedAmount
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

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

            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            expectedOnPool = underlyingToAdUnit(amountPerBorrower, normalizedVariableDebt);

            testEquality(inP2P, 0);
            testEquality(onPool, expectedOnPool);
        }

        // Borrower1 repays all of his debt
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
        //(Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);
        (Asset memory supply, Asset memory borrow) = getAssets(10_000 ether, 1, 0);

        // Borrower1 & supplier1 are matched for supplierAmount
        borrower1.supply(supply.poolToken, 2 * supply.amount);
        borrower1.borrow(borrow.poolToken, 2 * borrow.amount);

        supplier1.supply(borrow.poolToken, borrow.amount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            borrow.amount,
            lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
        );

        assertEq(onPoolSupplier, 0, "supplier1 on pool");
        assertEq(inP2PSupplier, inP2PBorrower1, "borrower1/supplier1 in P2P");
        assertEq(onPoolBorrower1, expectedOnPool, "borrower1 on pool");

        // Borrower1 repays 75% of borrowed amount
        borrower1.repay(borrow.poolToken, (borrow.amount * 2 * 75) / 100);

        // Check balances for borrower
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);

        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            (borrow.amount * 2 * 25) / 100,
            borrowP2PExchangeRate
        );

        assertApproxEq(
            inP2PBorrower1,
            expectedBorrowBalanceInP2P,
            1,
            "borrower1 in P2P after repay"
        );
        assertEq(onPoolBorrower1, 0, "borrower1 on pool after repay");

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            borrow.amount / 2,
            borrowP2PExchangeRate
        );
        uint256 expectedSupplyBalanceOnPool = underlyingToAdUnit(
            borrow.amount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        assertApproxEq(inP2PSupplier, expectedSupplyBalanceInP2P, 1, "supplier1 in P2P");
        assertApproxEq(onPoolSupplier, expectedSupplyBalanceOnPool, 1, "supplier1 on pool");
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
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

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

            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        // Borrower1 repays all of his debt
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
}
