// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRepay is TestSetup {
    using CompoundMath for uint256;

    function testRepay1() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        borrower1.approve(dai, amount);
        borrower1.repay(cDai, amount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        assertEq(inP2P, 0);
        assertEq(onPool, 0);
    }

    function testRepayAll() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        uint256 balanceBefore = borrower1.balanceOf(dai);
        borrower1.approve(dai, amount);
        borrower1.repay(cDai, type(uint256).max);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));
        uint256 balanceAfter = supplier1.balanceOf(dai);

        assertEq(inP2P, 0);
        assertEq(onPool, 0);
        assertEq(balanceBefore - balanceAfter, amount);
    }

    function testRepay2_1() public {
        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = suppliedAmount.div(ICToken(cDai).borrowIndex());

        assertEq(onPoolSupplier, 0, "supplier on pool");
        assertEq(onPoolBorrower1, expectedOnPool, "borrower on pool");
        assertEq(inP2PSupplier, inP2PBorrower1, "in peer-to-peer");

        // An available borrower onPool.
        uint256 availableBorrowerAmount = borrowedAmount / 4;
        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(cUsdc, to6Decimals(collateral));
        borrower2.borrow(cDai, availableBorrowerAmount);

        // Borrower1 repays 75% of suppliedAmount.
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(cDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower1 & borrower2.
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        (uint256 inP2PAvailableBorrower, uint256 onPoolAvailableBorrower) = morpho
        .borrowBalanceInOf(cDai, address(borrower2));
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
        uint256 expectedBorrowBalanceInP2P = ((25 * borrowedAmount) / 100).div(p2pBorrowIndex);

        assertApproxEq(inP2PBorrower1, inP2PAvailableBorrower, 1);
        assertApproxEq(inP2PBorrower1, expectedBorrowBalanceInP2P, 1);
        assertEq(onPoolBorrower1, 0);
        assertEq(onPoolAvailableBorrower, 0);

        // Check balances for supplier.
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertApproxEq(2 * inP2PBorrower1, inP2PSupplier, 1);
        assertEq(onPoolSupplier, 0);
    }

    function testRepay2_2() public {
        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 suppliedAmount = 10_000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched up to suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = suppliedAmount.div(ICToken(cDai).borrowIndex());

        assertEq(onPoolSupplier, 0);
        assertEq(onPoolBorrower1, expectedOnPool, "borrower1 on pool");
        assertEq(inP2PSupplier, inP2PBorrower1, "supplier1 in peer-to-peer");

        // NMAX borrowers have debt waiting on pool.
        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 inP2P;
        uint256 onPool;
        uint256 borrowIndex = ICToken(cDai).borrowIndex();

        // minus because borrower1 must not be counted twice !
        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (NMAX - 1);

        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, amountPerBorrower);

            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            expectedOnPool = amountPerBorrower.div(borrowIndex);

            assertEq(inP2P, 0);
            assertEq(onPool, expectedOnPool);
        }

        // Borrower1 repays all of his debt.
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        // His balance should be set to 0.
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        assertEq(onPoolBorrower1, 0);
        assertEq(inP2PBorrower1, 0);

        // Check balances for the supplier.
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 expectedSupplyBalanceInP2P = suppliedAmount.div(morpho.p2pBorrowIndex(cDai));

        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "supplier in peer-to-peer");
        assertEq(onPoolSupplier, 0, "supplier on pool");

        // Now test for each individual borrower that replaced the original.
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            uint256 expectedInP2P = expectedOnPool.mul(ICToken(cDai).borrowIndex()).div(
                morpho.p2pBorrowIndex(cDai)
            );

            assertApproxEq(inP2P, expectedInP2P, 1, "borrower in peer-to-peer");
            assertApproxEq(onPool, 0, 1e9, "borrower on pool");
        }
    }

    function testRepay2_3() public {
        uint256 suppliedAmount = 10_000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for supplierAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount).div(ICToken(cDai).borrowIndex());

        assertEq(onPoolSupplier, 0);
        assertEq(onPoolBorrower1, expectedOnPool);
        assertEq(inP2PSupplier, inP2PBorrower1);

        // Borrower1 repays 75% of borrowed amount.
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(cDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower.
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);

        uint256 expectedBorrowBalanceInP2P = ((25 * borrowedAmount) / 100).div(p2pBorrowIndex);

        assertApproxEq(inP2PBorrower1, expectedBorrowBalanceInP2P, 1);
        assertEq(onPoolBorrower1, 0);

        // Check balances for supplier.
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 expectedSupplyBalanceInP2P = (suppliedAmount / 2).div(p2pBorrowIndex);
        uint256 expectedSupplyBalanceOnPool = (suppliedAmount / 2).div(supplyPoolIndex);

        assertApproxEq(inP2PSupplier, expectedSupplyBalanceInP2P, 1);
        assertEq(onPoolSupplier, expectedSupplyBalanceOnPool);
    }

    function testRepay2_4() public {
        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 suppliedAmount = 10_000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = suppliedAmount.div(ICToken(cDai).borrowIndex());

        assertEq(onPoolSupplier, 0);
        assertEq(onPoolBorrower1, expectedOnPool);
        assertEq(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have borrowerAmount/2 (cumulated) of debt waiting on pool.
        uint256 NMAX = 20;
        createSigners(NMAX);

        // minus because borrower1 must not be counted twice !
        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (2 * (NMAX - 1));

        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, amountPerBorrower);
        }

        // Borrower1 repays all of his debt.
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(cDai, borrowedAmount);

        // Borrower1 balance should be set to 0.
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        assertEq(onPoolBorrower1, 0);
        assertEq(inP2PBorrower1, 0);

        // Check balances for the supplier.
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 expectedSupplyBalanceOnPool = (suppliedAmount / 2).div(
            ICToken(cDai).exchangeRateCurrent()
        );
        uint256 expectedSupplyBalanceInP2P = (suppliedAmount / 2).div(morpho.p2pBorrowIndex(cDai));

        assertApproxEq(inP2PSupplier, expectedSupplyBalanceInP2P, 1, "supplier in peer-to-peer");
        assertApproxEq(onPoolSupplier, expectedSupplyBalanceOnPool, 1, "supplier on pool");

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual borrower that replaced the original
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));

            uint256 expectedInP2P = amountPerBorrower.div(morpho.p2pBorrowIndex(cDai));

            assertEq(inP2P, expectedInP2P, "borrower in peer-to-peer");
            assertEq(onPool, 0, "borrower on pool");
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
        // Allows only 10 unmatch suppliers.
        setMaxGasForMatchingHelper(3e6, 3e6, 3e6, 2e6);

        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 20 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;
        uint256 expectedBorrowBalanceInP2P;

        // borrower1 and 100 suppliers are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        createSigners(30);
        uint256 matched;

        // 2 * NMAX suppliers supply suppliedAmount.
        for (uint256 i = 0; i < 20; i++) {
            suppliers[i].approve(dai, suppliedAmount);
            suppliers[i].supply(cDai, suppliedAmount);
            matched += suppliedAmount.div(morpho.p2pSupplyIndex(cDai));
        }

        {
            uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
            expectedBorrowBalanceInP2P = borrowedAmount.div(p2pBorrowIndex);

            // Check balances after match of supplier1
            (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
                cDai,
                address(borrower1)
            );
            assertApproxEq(onPoolBorrower, 0, 10, "borrower on pool");
            assertApproxEq(
                inP2PBorrower,
                expectedBorrowBalanceInP2P,
                10,
                "borrower in peer-to-peer"
            );

            uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
            uint256 expectedSupplyBalanceInP2P = suppliedAmount.div(p2pSupplyIndex);

            for (uint256 i = 0; i < 20; i++) {
                (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
                    cDai,
                    address(suppliers[i])
                );
                assertEq(onPoolSupplier, 0, "supplier on pool 1");
                assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "supplier in peer-to-peer 1");
            }

            // Borrower repays max.
            // Should create a delta on suppliers side.
            borrower1.approve(dai, type(uint256).max);
            borrower1.repay(cDai, type(uint256).max);

            {
                // Check balances for borrower1.
                (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.supplyBalanceInOf(
                    cDai,
                    address(borrower1)
                );

                assertEq(onPoolBorrower1, 0);
                assertEq(inP2PBorrower1, 0);
            }

            // There should be a delta.
            // The amount unmatched during the repay.
            uint256 unmatched = 10 * expectedSupplyBalanceInP2P.mul(morpho.p2pSupplyIndex(cDai));
            // The difference between the previous matched amount and the amout unmatched creates a delta.
            uint256 expectedp2pSupplyDeltaInUnderlying = (matched.mul(morpho.p2pSupplyIndex(cDai)) -
                unmatched);
            uint256 expectedp2pSupplyDelta = (matched.mul(morpho.p2pSupplyIndex(cDai)) - unmatched)
            .div(ICToken(cDai).exchangeRateCurrent());

            (uint256 p2pSupplyDelta, , , ) = morpho.deltas(cDai);
            assertEq(p2pSupplyDelta, expectedp2pSupplyDelta, "supply delta 1");

            // Supply delta matching by a new borrower.
            borrower2.approve(usdc, to6Decimals(collateral));
            borrower2.supply(cUsdc, to6Decimals(collateral));
            borrower2.borrow(cDai, expectedp2pSupplyDeltaInUnderlying / 2);

            (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower2));
            expectedBorrowBalanceInP2P = (expectedp2pSupplyDeltaInUnderlying / 2).div(
                p2pBorrowIndex
            );

            (p2pSupplyDelta, , , ) = morpho.deltas(cDai);
            assertEq(p2pSupplyDelta, expectedp2pSupplyDelta / 2, "supply delta unexpected");
            assertEq(onPoolBorrower, 0, "on pool not unexpected");
            assertEq(inP2PBorrower, expectedBorrowBalanceInP2P, "in peer-to-peer unexpected");
        }

        {
            Vars memory oldVars;
            Vars memory newVars;

            (oldVars.SP2PD, , oldVars.SP2PA, ) = morpho.deltas(cDai);
            oldVars.SPI = ICToken(cDai).exchangeRateCurrent();
            oldVars.SP2PER = morpho.p2pSupplyIndex(cDai);
            (oldVars.BPY, ) = getApproxBPYs(cDai);

            move1000BlocksForward(cDai);

            morpho.updateP2PIndexes(cDai);

            (newVars.SP2PD, , newVars.SP2PA, ) = morpho.deltas(cDai);
            newVars.SPI = ICToken(cDai).exchangeRateCurrent();
            newVars.SP2PER = morpho.p2pSupplyIndex(cDai);
            newVars.LR = ICToken(cDai).supplyRatePerBlock();
            newVars.VBR = ICToken(cDai).borrowRatePerBlock();

            uint256 shareOfTheDelta = newVars.SP2PD.mul(newVars.SPI).div(oldVars.SP2PER).div(
                newVars.SP2PA
            );

            uint256 expectedSP2PER = oldVars.SP2PER.mul(
                _computeCompoundedInterest(oldVars.BPY, 1_000).mul(WAD - shareOfTheDelta) +
                    shareOfTheDelta.mul(newVars.SPI).div(oldVars.SPI)
            );

            assertApproxEq(
                expectedSP2PER,
                newVars.SP2PER,
                (expectedSP2PER * 2) / 100,
                "SP2PER not expected"
            );

            uint256 expectedSupplyBalanceInUnderlying = suppliedAmount.div(oldVars.SP2PER).mul(
                expectedSP2PER
            );

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
                    cDai,
                    address(suppliers[i])
                );

                assertApproxEq(
                    inP2PSupplier.mul(newVars.SP2PER),
                    expectedSupplyBalanceInUnderlying,
                    (expectedSupplyBalanceInUnderlying * 2) / 100,
                    "supplier in peer-to-peer 2"
                );
                assertEq(onPoolSupplier, 0, "supplier on pool 2");
            }
        }

        // Supply delta reduction with suppliers withdrawing
        for (uint256 i = 10; i < 20; i++) {
            suppliers[i].withdraw(cDai, suppliedAmount);
        }

        (uint256 p2pSupplyDeltaAfter, , , ) = morpho.deltas(cDai);
        assertApproxEq(p2pSupplyDeltaAfter, 0, 1, "supply delta after");

        (uint256 inP2PBorrower2, uint256 onPoolBorrower2) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower2)
        );

        assertEq(inP2PBorrower2, expectedBorrowBalanceInP2P, "borrower2 in peer-to-peer");
        assertEq(onPoolBorrower2, 0, "borrower2 on pool");
    }

    function testDeltaRepayAll() public {
        // Allows only 10 unmatch suppliers.
        setMaxGasForMatchingHelper(3e6, 3e6, 3e6, 2.4e6);

        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 20 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // borrower1 and 100 suppliers are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        createSigners(30);

        // 2 * NMAX suppliers supply suppliedAmount.
        for (uint256 i = 0; i < 20; i++) {
            suppliers[i].approve(dai, suppliedAmount);
            suppliers[i].supply(cDai, suppliedAmount);
        }

        // Borrower repays max.
        // Should create a delta on suppliers side.
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        move1000BlocksForward(cDai);

        for (uint256 i; i < 20; i++) {
            suppliers[i].withdraw(cDai, type(uint256).max);
        }
    }

    function testFailRepayZero() public {
        morpho.repay(cDai, 0);
    }

    function testRepayRepayOnBehalf() public {
        uint256 amount = 1 ether;
        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        // Someone repays on behalf of the morpho.
        supplier2.approve(dai, cDai, amount);
        hevm.prank(address(supplier2));
        ICToken(cDai).repayBorrowBehalf(address(morpho), amount);
        hevm.stopPrank();

        // Borrower1 repays on pool. Not supposed to revert.
        borrower1.approve(dai, amount);
        borrower1.repay(cDai, amount);
    }

    function testRepayOnPoolThreshold() public {
        uint256 amountRepaid = 1e6;

        borrower1.approve(usdc, to6Decimals(2 ether));
        borrower1.supply(cUsdc, to6Decimals(2 ether));

        borrower1.borrow(cDai, 1 ether);

        uint256 onCompBeforeRepay = ICToken(cDai).borrowBalanceCurrent(address(morpho));
        (, uint256 onPoolBeforeRepay) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        // We check that repaying a dust quantity leads to a diminishing debt in both cToken & on Morpho.
        borrower1.approve(dai, amountRepaid);
        borrower1.repay(cDai, amountRepaid);

        uint256 onCompAfterRepay = ICToken(cDai).borrowBalanceCurrent(address(morpho));
        (, uint256 onPoolAfterRepay) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        assertLt(onCompAfterRepay, onCompBeforeRepay, "on Comp");
        assertLt(onPoolAfterRepay, onPoolBeforeRepay, "on Morpho");
    }
}
