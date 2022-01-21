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

        borrower1.approve(supply.underlying, supply.amount + 1);
        borrower1.supply(supply.poolToken, supply.amount + 1);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        borrower1.approve(borrow.underlying, borrow.amount);
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
    function test_repay_4_2_1(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        // Borrower1 & supplier1 are matched for borrow.amount
        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        supplier1.approve(borrow.underlying, supply.amount);
        supplier1.supply(borrow.poolToken, supply.amount);

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

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // An available borrower onPool
        uint256 availableBorrowerAmount = borrow.amount / 4;
        borrower2.approve(supply.underlying, supply.amount);
        borrower2.supply(supply.poolToken, supply.amount);
        borrower2.borrow(borrow.poolToken, availableBorrowerAmount);

        // Borrower1 repays 75% of suppliedAmount
        borrower1.approve(borrow.underlying, (75 * borrow.amount) / 100);
        borrower1.repay(borrow.poolToken, (75 * borrow.amount) / 100);

        // Check balances for borrower1 & borrower2
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PAvailableBorrower, uint256 onPoolAvailableBorrower) = positionsManager
        .borrowBalanceInOf(borrow.poolToken, address(borrower2));
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(borrow.poolToken);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            (25 * borrow.amount) / 100,
            borrowP2PExchangeRate
        );

        testEquality(inP2PBorrower1, inP2PAvailableBorrower);
        testEquality(inP2PBorrower1, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower1, 0);
        testEquality(onPoolAvailableBorrower, 0);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );
        testEquality(2 * inP2PBorrower1, inP2PSupplier);
        testEquality(onPoolSupplier, 0);
    }

    //   - 4.2.2 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they borrow enough to cover for the repaid liquidity.
    //             First, his debt `onPool` is repaid, his matched liquidity is replaced by NMAX (or less) borrowers up to his repaid amount.
    function test_repay_4_2_2(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        /* STACK TOO DEEP 
        // Borrower1 & supplier1 are matched up to borrow.amount
        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        supplier1.approve(borrow.underlying, borrow.amount);
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

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have debt waiting on pool
        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        uint256 inP2P;
        uint256 onPool;
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            borrow.underlying
        );

        uint256 amountPerBorrower = (supply.amount - borrow.amount) / (NMAX - 1);
        for (uint256 i = 1; i < NMAX; i++) {
            borrowers[i].approve(supply.underlying, supply.amount);
            borrowers[i].supply(supply.poolToken, supply.amount);
            borrowers[i].borrow(borrow.poolToken, borrow.amount);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(
                borrow.poolToken,
                address(borrowers[i])
            );
            expectedOnPool = underlyingToAdUnit(borrow.amount, normalizedVariableDebt);

            testEquality(inP2P, 0);
            testEquality(onPool, expectedOnPool);
        }

        // Borrower1 repays all of his debt
        borrower1.approve(borrow.underlying, borrow.amount);
        borrower1.repay(borrow.poolToken, borrow.amount);

        // His balance should be set to 0
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PBorrower1, 0);

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(borrow.poolToken);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            borrow.amount,
            borrowP2PExchangeRate
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, 0);

        // Now test for each individual borrower that replaced the original
        for (uint256 i = 1; i < borrowers.length; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(
                borrow.poolToken,
                address(borrowers[i])
            );

            testEquality(inP2P, underlyingToP2PUnit(borrow.amount, borrowP2PExchangeRate));
            testEquality(onPool, 0);
        }
        */
    }

    //   - 4.2.3 - There are no borrowers `onPool` to replace him `inP2P`. After repaying the amount `onPool`,
    //             his P2P match(es) will be unmatched and the corresponding supplier(s) will be placed on pool.
    function test_repay_4_2_3(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
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

    //   - 4.2.4 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they don't borrow enough to cover for the withdrawn liquidity.
    //             First, the `onPool` liquidity is withdrawn, then we proceed to NMAX (or less) matches. Finally, some suppliers are unmatched for an amount equal to the remaining to withdraw.
    //             ⚠️ most gas expensive repay scenario.
    function test_repay_4_2_4(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
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
        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

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
}
