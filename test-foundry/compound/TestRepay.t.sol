// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRepay is TestSetup {
    using CompoundMath for uint256;

    function testRepay1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        borrower1.approve(dai, amount);
        borrower1.repay(cDai, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
    }

    function testRepayAll() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        uint256 balanceBefore = borrower1.balanceOf(dai);
        borrower1.approve(dai, amount);
        borrower1.repay(cDai, type(uint256).max);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 balanceAfter = supplier1.balanceOf(dai);

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
        testEquality(balanceBefore - balanceAfter, amount);
    }

    function testRepay2_1() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToDebtUnit(
            suppliedAmount,
            ICToken(cDai).exchangeRateCurrent()
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // An available borrower onPool
        uint256 availableBorrowerAmount = borrowedAmount / 4;
        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(cUsdc, to6Decimals(collateral));
        borrower2.borrow(cDai, availableBorrowerAmount);

        // Borrower1 repays 75% of suppliedAmount
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(cDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower1 & borrower2
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PAvailableBorrower, uint256 onPoolAvailableBorrower) = positionsManager
        .borrowBalanceInOf(cDai, address(borrower2));
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
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
            cDai,
            address(supplier1)
        );
        testEquality(2 * inP2PBorrower1, inP2PSupplier);
        testEquality(onPoolSupplier, 0);
    }

    function testRepay2_2() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched up to suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToDebtUnit(
            suppliedAmount,
            ICToken(cDai).exchangeRateCurrent()
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have debt waiting on pool
        uint8 NMAX = 20;
        createSigners(NMAX);

        uint256 inP2P;
        uint256 onPool;
        uint256 normalizedVariableDebt = ICToken(cDai).exchangeRateCurrent();

        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (NMAX - 1);
        // minus because borrower1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, amountPerBorrower);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrowers[i]));
            expectedOnPool = underlyingToDebtUnit(amountPerBorrower, normalizedVariableDebt);

            testEquality(inP2P, 0);
            testEquality(onPool, expectedOnPool);
        }

        // Borrower1 repays all of his debt
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(cDai, borrowedAmount);

        // His balance should be set to 0
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PBorrower1, 0);

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            suppliedAmount,
            borrowP2PExchangeRate
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, 0);

        // Now test for each individual borrower that replaced the original
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrowers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, borrowP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower);
            testEquality(onPool, 0);
        }
    }

    function testRepay2_3() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for supplierAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToDebtUnit(
            suppliedAmount,
            ICToken(cDai).exchangeRateCurrent()
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // Borrower1 repays 75% of borrowed amount
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(cDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);

        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            (25 * borrowedAmount) / 100,
            borrowP2PExchangeRate
        );

        testEquality(inP2PBorrower1, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower1, 0);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            suppliedAmount / 2,
            borrowP2PExchangeRate
        );
        uint256 expectedSupplyBalanceOnPool = underlyingToDebtUnit(
            suppliedAmount / 2,
            supplyPoolIndex
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool);
    }

    function testRepay2_4() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToDebtUnit(
            suppliedAmount,
            ICToken(cDai).exchangeRateCurrent()
        );

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have borrowerAmount/2 (cumulated) of debt waiting on pool
        uint8 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (2 * (NMAX - 1));
        // minus because borrower1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, amountPerBorrower);
        }

        // Borrower1 repays all of his debt
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(cDai, borrowedAmount);

        // His balance should be set to 0
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PBorrower1, 0);

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();

        uint256 expectedSupplyBalanceOnPool = underlyingToP2PUnit(
            suppliedAmount / 2,
            supplyPoolIndex
        );
        uint256 expectedSupplyBalanceInP2P = underlyingToDebtUnit(
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

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrowers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, borrowP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower);
            testEquality(onPool, 0);
        }
    }

    struct Vars {
        uint256 LR;
        uint256 SPI;
        uint256 BPY;
        uint256 VBR;
        uint256 SP2PD;
        uint256 SP2PA;
        uint256 SP2PER;
    }

    function testDeltaRepay() public {
        // Allows only 10 unmatch suppliers
        setMaxGasHelper(3e6, 3e6, 3e6, 2.4e6);

        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 20 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;
        uint256 expectedBorrowBalanceInP2P;

        // borrower1 and 100 suppliers are matched for borrowedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        createSigners(30);

        // 2 * NMAX suppliers supply suppliedAmount
        for (uint256 i = 0; i < 20; i++) {
            suppliers[i].approve(dai, suppliedAmount);
            suppliers[i].supply(cDai, suppliedAmount);
        }

        {
            uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
            expectedBorrowBalanceInP2P = underlyingToP2PUnit(borrowedAmount, borrowP2PExchangeRate);

            // Check balances after match of supplier1
            (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
                cDai,
                address(borrower1)
            );
            testEquality(onPoolBorrower, 0);
            testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);

            uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
            uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
                suppliedAmount,
                supplyP2PExchangeRate
            );

            for (uint256 i = 0; i < 20; i++) {
                (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager
                .supplyBalanceInOf(cDai, address(suppliers[i]));
                testEquality(onPoolSupplier, 0);
                testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
            }

            // Borrower repays max
            // Should create a delta on suppliers side
            borrower1.approve(dai, type(uint256).max);
            borrower1.repay(cDai, type(uint256).max);

            // Check balances for borrower1
            (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.supplyBalanceInOf(
                cDai,
                address(borrower1)
            );
            testEquality(onPoolBorrower1, 0);
            testEquality(inP2PBorrower1, 0);

            // There should be a delta
            uint256 expectedSupplyP2PDeltaInUnderlying = 10 * suppliedAmount;
            uint256 expectedSupplyP2PDelta = underlyingToPoolSupplyBalance(
                expectedSupplyP2PDeltaInUnderlying,
                ICToken(cDai).exchangeRateCurrent()
            );
            (uint256 supplyP2PDelta, , , ) = positionsManager.deltas(cDai);
            testEquality(supplyP2PDelta, expectedSupplyP2PDelta);

            // Supply delta matching by a new borrower
            borrower2.approve(usdc, to6Decimals(collateral));
            borrower2.supply(cUsdc, to6Decimals(collateral));
            borrower2.borrow(cDai, expectedSupplyP2PDeltaInUnderlying / 2);

            (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
                cDai,
                address(borrower2)
            );
            expectedBorrowBalanceInP2P = underlyingToP2PUnit(
                expectedSupplyP2PDeltaInUnderlying / 2,
                borrowP2PExchangeRate
            );

            (supplyP2PDelta, , , ) = positionsManager.deltas(cDai);
            testEquality(supplyP2PDelta, expectedSupplyP2PDelta / 2);
            testEquality(onPoolBorrower, 0);
            testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        }

        {
            Vars memory oldVars;
            Vars memory newVars;

            (oldVars.SP2PD, , oldVars.SP2PA, ) = positionsManager.deltas(cDai);
            oldVars.SPI = ICToken(cDai).exchangeRateCurrent();
            oldVars.SP2PER = marketsManager.supplyP2PExchangeRate(cDai);
            oldVars.BPY = marketsManager.supplyP2PBPY(cDai);

            hevm.roll(block.number + 100);

            marketsManager.updateRates(cDai);

            (newVars.SP2PD, , newVars.SP2PA, ) = positionsManager.deltas(cDai);
            newVars.SPI = ICToken(cDai).exchangeRateCurrent();
            newVars.SP2PER = marketsManager.supplyP2PExchangeRate(cDai);
            newVars.LR = ICToken(cDai).supplyRatePerBlock();
            newVars.VBR = ICToken(cDai).borrowRatePerBlock();

            uint256 shareOfTheDelta = newVars.SP2PD.mul(oldVars.SP2PER).div(newVars.SPI).div(
                newVars.SP2PA
            );

            uint256 expectedSP2PER = oldVars.SP2PER.mul(
                _computeCompoundedInterest(oldVars.BPY, 100).mul(WAD - shareOfTheDelta) +
                    shareOfTheDelta.mul(newVars.SPI).div(oldVars.SPI)
            );

            testEquality(expectedSP2PER, newVars.SP2PER, "SP2PER not expected");

            uint256 expectedSupplyBalanceInUnderlying = suppliedAmount.div(oldVars.SP2PER).mul(
                expectedSP2PER
            );

            for (uint256 i = 0; i < 10; i++) {
                (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager
                .supplyBalanceInOf(cDai, address(suppliers[i]));
                testEquality(
                    p2pUnitToUnderlying(inP2PSupplier, newVars.SP2PER),
                    expectedSupplyBalanceInUnderlying,
                    "not expected balance"
                );
                testEquality(onPoolSupplier, 0);
            }
        }

        // Supply delta reduction with suppliers withdrawing
        for (uint256 i = 0; i < 10; i++) {
            suppliers[i].withdraw(cDai, suppliedAmount);
        }

        (uint256 supplyP2PDeltaAfter, , , ) = positionsManager.deltas(cDai);
        testEquality(supplyP2PDeltaAfter, 0);

        (uint256 inP2PBorrower2, uint256 onPoolBorrower2) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower2)
        );

        testEquality(inP2PBorrower2, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower2, 0);
    }

    // TODO
    function testDeltaRepayAll() public {}

    // TODO
    function testFailRepayZero() public {}
}
