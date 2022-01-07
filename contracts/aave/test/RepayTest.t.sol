// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./TestSetup.sol";

contract RepayTest is TestSetup {
    // - 4.1 - The borrower repays less than his `onPool` balance. The liquidity is repaid on his `onPool` balance.
    function testRepay_4_1() public {
        uint256 amount = 100 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            amount,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        assertEq(inP2P, 0);
        assertLe(get_abs_diff(onPool, expectedOnPool), 2);

        borrower1.approve(dai, amount);
        borrower1.repay(aDai, amount);

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        assertEq(inP2P, 0);
        assertEq(onPool, 0);
    }

    // - 4.2 - The borrower repays more than his `onPool` balance.
    //   - 4.2.1 - There is a borrower `onPool` available to replace him `inP2P`.
    //             First, his debt `onPool` is repaid, his matched debt is replaced by the available borrower up to his repaid amount.
    function testRepay_4_2_1() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowedAmount = 20 ether;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for 10 ETH
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
            10 ether,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        assertEq(onPoolSupplier, 0);
        assertLe(get_abs_diff(onPoolBorrower1, expectedOnPool), 2);
        assertLe(get_abs_diff(inP2PSupplier, inP2PBorrower1), 2);

        // An available borrower onPool
        uint256 availableBorrowerAmount = 5 ether;
        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(aUsdc, to6Decimals(collateral));
        borrower2.borrow(aDai, availableBorrowerAmount);

        // Borrower1 repays 15 ETH
        borrower1.approve(dai, 15 ether);
        borrower1.repay(aDai, 15 ether);

        // Check balances for borrower
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PAvailableBorrower, uint256 onPoolAvailableBorrower) = positionsManager
            .borrowBalanceInOf(aDai, address(borrower2));

        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(5 ether, p2pExchangeRate);

        assertLe(get_abs_diff(inP2PBorrower1, inP2PAvailableBorrower), 2);
        assertLe(get_abs_diff(inP2PBorrower1, expectedBorrowBalanceInP2P), 2);
        assertLe(get_abs_diff(onPoolBorrower1, 0), 2);
        assertLe(get_abs_diff(onPoolAvailableBorrower, 0), 2);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        assertLe(get_abs_diff(2 * inP2PBorrower1, inP2PSupplier), 2);
        assertLe(get_abs_diff(onPoolSupplier, 0), 2);
    }

    //   - 4.2.2 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they borrow enough to cover for the repaid liquidity.
    //             First, his debt `onPool` is repaid, his matched liquidity is replaced by NMAX (or less) borrowers up to his repaid amount.
    function testRepay_4_2_2() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowedAmount = 20 ether;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for 10 ETH
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
            10 ether,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        assertLe(get_abs_diff(onPoolSupplier, 0), 1, "onPool Supplier");
        assertLe(get_abs_diff(onPoolBorrower1, expectedOnPool), 1, "onPool borrower1");
        assertLe(get_abs_diff(inP2PSupplier, inP2PBorrower1), 1, "inP2P borrower & supplier");

        // NMAX borrowers have 10 ETH (cumulated) of debt waiting on pool
        setNMAXAndCreateSigners(20);
        uint256 NMAX = positionsManager.NMAX();

        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (NMAX - 1);
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

        assertLe(get_abs_diff(onPoolBorrower1, 0), 1, "onPool borrower1 after repay");
        assertLe(get_abs_diff(inP2PBorrower1, 0), 1, "inP2P borrower1 after repay");
        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToAdUnit(10 ether, p2pExchangeRate);

        assertLe(
            get_abs_diff(inP2PSupplier, expectedSupplyBalanceInP2P),
            1,
            "inP2P supplier after repay"
        );
        assertLe(get_abs_diff(onPoolSupplier, 0), 1, "onPool supplier after repay");

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual borrower that replaced the original
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertLe(
                get_abs_diff(expectedInP2P, amountPerBorrower),
                1,
                "inP2P available borrowers"
            );
            assertLe(get_abs_diff(onPool, 0), 1, "onPool available borrowers");
        }
    }

    //   - 4.2.3 - There are no borrowers `onPool` to replace him `inP2P`. After repaying the amount `onPool`,
    //             his P2P match(es) will be unmatched and the corresponding supplier(s) will be placed on pool.
    function testRepay_4_2_3() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowedAmount = 20 ether;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for 10 ETH
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
            10 ether,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        assertLe(get_abs_diff(onPoolSupplier, 0), 2);
        assertLe(get_abs_diff(onPoolBorrower1, expectedOnPool), 2);
        assertLe(get_abs_diff(inP2PSupplier, inP2PBorrower1), 2);

        // Borrower1 repays 15 ETH
        borrower1.approve(dai, 15 ether);
        borrower1.repay(aDai, 15 ether);

        // Check balances for borrower
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(5 ether, p2pExchangeRate);

        assertLe(
            get_abs_diff(inP2PBorrower1, expectedBorrowBalanceInP2P),
            1,
            "inP2P borrower after repay"
        );
        assertLe(get_abs_diff(onPoolBorrower1, 0), 1, "onPool borrower after repay");

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(5 ether, p2pExchangeRate);
        uint256 expectedSupplyBalanceOnPool = underlyingToAdUnit(5 ether, normalizedIncome);

        assertLe(get_abs_diff(inP2PSupplier, expectedSupplyBalanceInP2P), 2);
        assertLe(get_abs_diff(onPoolSupplier, expectedSupplyBalanceOnPool), 2);
    }

    //   - 4.2.4 - There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they don't supply enough to cover for the withdrawn liquidity.
    //             First, the `onPool` liquidity is withdrawn, then we proceed to NMAX (or less) matches. Finally, some suppliers are unmatched for an amount equal to the remaining to withdraw.
    //             ⚠️ most gas expensive repay scenario.
    function testRepay_4_2_4() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for 10 ETH
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
            10 ether,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        assertLe(get_abs_diff(onPoolSupplier, 0), 1, "onPool Supplier");
        assertLe(get_abs_diff(onPoolBorrower1, expectedOnPool), 1, "onPool borrower1");
        assertLe(get_abs_diff(inP2PSupplier, inP2PBorrower1), 1, "inP2P borrower & supplier");

        // NMAX borrowers have 10 ETH (cumulated) of debt waiting on pool
        marketsManager.setMaxNumberOfUsersInTree(3);
        uint256 NMAX = positionsManager.NMAX();

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

        assertLe(get_abs_diff(onPoolBorrower1, 0), 1, "onPool borrower1 after repay");
        assertLe(get_abs_diff(inP2PBorrower1, 0), 1, "inP2P borrower1 after repay");

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);

        uint256 expectedSupplyBalanceOnPool = underlyingToP2PUnit(5 ether, normalizedIncome);
        uint256 expectedSupplyBalanceInP2P = underlyingToAdUnit(5 ether, p2pExchangeRate);

        assertLe(
            get_abs_diff(inP2PSupplier, expectedSupplyBalanceInP2P),
            1,
            "inP2P supplier after repay"
        );
        assertLe(
            get_abs_diff(onPoolSupplier, expectedSupplyBalanceOnPool),
            1,
            "onPool supplier after repay"
        );

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual borrower that replaced the original
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertLe(
                get_abs_diff(expectedInP2P, amountPerBorrower),
                1,
                "inP2P available borrowers"
            );
            assertLe(get_abs_diff(onPool, 0), 1, "onPool available borrowers");
        }
    }
}
