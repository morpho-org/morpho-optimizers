// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/IMorpho.sol";

import {Attacker} from "./helpers/Attacker.sol";
import "./setup/TestSetup.sol";

contract TestWithdraw is TestSetup {
    using CompoundMath for uint256;

    function testWithdraw1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        borrower1.borrow(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.withdraw(cUsdc, to6Decimals(collateral));
    }

    function testWithdraw2() public {
        uint256 amount = 10000 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(cUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(2 * amount).div(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(inP2P, 0);
        assertEq(onPool, expectedOnPool);

        supplier1.withdraw(cUsdc, to6Decimals(amount));

        (inP2P, onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        assertEq(inP2P, 0);
        assertApproxEq(onPool, expectedOnPool / 2, 1);
    }

    function testWithdrawAll() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(cUsdc, to6Decimals(amount));

        uint256 balanceBefore = supplier1.balanceOf(usdc);
        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(amount).div(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(inP2P, 0);
        assertEq(onPool, expectedOnPool);

        supplier1.withdraw(cUsdc, type(uint256).max);

        uint256 balanceAfter = supplier1.balanceOf(usdc);
        (inP2P, onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        assertEq(inP2P, 0, "in P2P");
        assertApproxEq(onPool, 0, 1e5, "on Pool");
        assertApproxEq(balanceAfter - balanceBefore, to6Decimals(amount), 1, "balance");
    }

    function testWithdraw3_1() public {
        uint256 borrowedAmount = 10000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());

        assertEq(onPoolSupplier, expectedOnPool);
        assertEq(onPoolBorrower1, 0);
        assertEq(inP2PSupplier, inP2PBorrower1);

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(cDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(cDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPoolSupplier, 0);
        assertApproxEq(inP2PSupplier, 0, 1);

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier2));
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 expectedInP2P = (suppliedAmount / 2).div(p2pSupplyIndex);
        assertApproxEq(onPoolSupplier, expectedOnPool, 1);
        assertApproxEq(inP2PSupplier, expectedInP2P, 1);

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(cDai, address(borrower1));
        assertEq(onPoolBorrower1, 0);
        assertApproxEq(inP2PSupplier, inP2PBorrower1, 1);
    }

    function testWithdraw3_2() public {
        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());

        assertEq(onPoolSupplier, expectedOnPool);
        assertEq(onPoolBorrower, 0);
        assertEq(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        // minus 1 because supplier1 must not be counted twice !
        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (NMAX - 1);

        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        // supplier1 withdraws suppliedAmount.
        supplier1.withdraw(cDai, type(uint256).max);

        // Check balances for supplier1.
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPoolSupplier, 0);
        assertApproxEq(inP2PSupplier, 0, 1);

        // Check balances for the borrower.
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowBalanceInP2P = borrowedAmount.div(morpho.p2pSupplyIndex(cDai));

        assertApproxEq(inP2PBorrower, expectedBorrowBalanceInP2P, 1, "borrower in P2P");
        assertApproxEq(onPoolBorrower, 0, 1e10, "borrower on Pool");

        // Now test for each individual supplier that replaced the original.
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));
            uint256 expectedInP2P = amountPerSupplier.div(morpho.p2pSupplyIndex(cDai));

            assertEq(inP2P, expectedInP2P, "in P2P");
            assertEq(onPool, 0, "on pool");
        }
    }

    function testWithdraw3_3() public {
        uint256 borrowedAmount = 10_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());

        assertEq(onPoolSupplier, expectedOnPool);
        assertEq(onPoolBorrower, 0);
        assertEq(inP2PSupplier, inP2PBorrower);

        // Supplier1 withdraws 75% of supplied amount
        uint256 toWithdraw = (75 * suppliedAmount) / 100;
        supplier1.withdraw(cDai, toWithdraw);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 expectedBorrowBalanceInP2P = (borrowedAmount / 2).div(p2pSupplyIndex);

        // The amount withdrawn from supplier1 minus what is on pool will be removed from the borrower P2P's position.
        uint256 expectedBorrowBalanceOnPool = (toWithdraw -
            onPoolSupplier.mul(ICToken(cDai).exchangeRateCurrent()))
        .div(ICToken(cDai).borrowIndex());

        assertEq(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in P2P");
        assertApproxEq(onPoolBorrower, expectedBorrowBalanceOnPool, 1e3, "borrower on Pool");

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 expectedSupplyBalanceInP2P = ((25 * suppliedAmount) / 100).div(p2pSupplyIndex);

        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "supplier in P2P");
        assertEq(onPoolSupplier, 0, "supplier on Pool");
    }

    function testWithdraw3_4() public {
        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());

        assertEq(onPoolSupplier, expectedOnPool, "supplier on Pool 1");
        assertEq(onPoolBorrower, 0, "borrower on Pool 1");
        assertEq(inP2PSupplier, inP2PBorrower, "supplier in P2P 1");

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        // minus 1 because supplier1 must not be counted twice !
        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (NMAX - 1));
        uint256[] memory rates = new uint256[](NMAX);

        uint256 matchedAmount;
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            rates[i] = ICToken(cDai).exchangeRateCurrent();

            matchedAmount += getBalanceOnCompound(
                amountPerSupplier,
                ICToken(cDai).exchangeRateCurrent()
            );

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount.
        supplier1.withdraw(cDai, suppliedAmount);

        uint256 halfBorrowedAmount = borrowedAmount / 2;

        {
            // Check balances for supplier1.
            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
            assertEq(onPoolSupplier, 0, "supplier on Pool 2");
            assertApproxEq(inP2PSupplier, 0, 1, "supplier in P2P 2");

            (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower1));

            uint256 expectedBorrowBalanceInP2P = halfBorrowedAmount.div(
                morpho.p2pSupplyIndex(cDai)
            );
            uint256 expectedBorrowBalanceOnPool = halfBorrowedAmount.div(
                ICToken(cDai).borrowIndex()
            );

            assertEq(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in P2P 2");
            assertApproxEq(onPoolBorrower, expectedBorrowBalanceOnPool, 1e10, "borrower on Pool 2");
        }

        // Check balances for the borrower.

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original.
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));

            assertEq(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(morpho.p2pSupplyIndex(cDai)),
                "supplier in P2P"
            );
            assertEq(onPool, 0, "supplier on pool");

            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            assertEq(inP2P, 0, "borrower in P2P");
        }
    }

    struct Vars {
        uint256 LR;
        uint256 BPY;
        uint256 VBR;
        uint256 NVD;
        uint256 BP2PD;
        uint256 BP2PA;
        uint256 BP2PER;
    }

    function testDeltaWithdraw() public {
        // 2e6 allows only 10 unmatch borrowers.
        setMaxGasForMatchingHelper(3e6, 3e6, 2e6, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount + 7;
        uint256 expectedSupplyBalanceInP2P;

        // supplier1 and 20 borrowers are matched for suppliedAmount.
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        createSigners(30);
        uint256 matched;

        // 2 * NMAX borrowers borrow borrowedAmount.
        for (uint256 i; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, borrowedAmount, type(uint64).max);
            matched += borrowedAmount.div(morpho.p2pBorrowIndex(cDai));
        }

        {
            uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
            expectedSupplyBalanceInP2P = suppliedAmount.div(p2pSupplyIndex);

            // Check balances after match of supplier1 and borrowers.
            (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
                cDai,
                address(supplier1)
            );
            assertEq(onPoolSupplier, 0);
            assertApproxEq(inP2PSupplier, expectedSupplyBalanceInP2P, 10);

            uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
            uint256 expectedBorrowBalanceInP2P = borrowedAmount.div(p2pBorrowIndex);

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
                    cDai,
                    address(borrowers[i])
                );
                assertEq(onPoolBorrower, 0);
                assertEq(inP2PBorrower, expectedBorrowBalanceInP2P);
            }

            // Supplier withdraws max.
            // Should create a delta on borrowers side.
            supplier1.withdraw(cDai, type(uint256).max);

            // Check balances for supplier1.
            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
            assertEq(onPoolSupplier, 0);
            assertApproxEq(inP2PSupplier, 0, 1);

            // There should be a delta.
            // The amount unmatched during the withdraw.
            uint256 unmatched = 10 * expectedBorrowBalanceInP2P.mul(morpho.p2pBorrowIndex(cDai));
            // The difference between the previous matched amount and the amout unmatched creates a delta.
            uint256 expectedp2pBorrowDeltaInUnderlying = (matched.mul(morpho.p2pBorrowIndex(cDai)) -
                unmatched);
            uint256 expectedp2pBorrowDelta = (matched.mul(morpho.p2pBorrowIndex(cDai)) - unmatched)
            .div(ICToken(cDai).borrowIndex());

            (, uint256 p2pBorrowDelta, , ) = morpho.deltas(cDai);
            assertEq(p2pBorrowDelta, expectedp2pBorrowDelta, "borrow Delta not expected 1");

            // Borrow delta matching by new supplier.
            supplier2.approve(dai, expectedp2pBorrowDeltaInUnderlying / 2);
            supplier2.supply(cDai, expectedp2pBorrowDeltaInUnderlying / 2);

            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier2));
            expectedSupplyBalanceInP2P = (expectedp2pBorrowDeltaInUnderlying / 2).div(
                p2pSupplyIndex
            );

            (, p2pBorrowDelta, , ) = morpho.deltas(cDai);
            assertApproxEq(
                p2pBorrowDelta,
                expectedp2pBorrowDelta / 2,
                1,
                "borrow Delta not expected 2"
            );
            assertEq(onPoolSupplier, 0, "on pool supplier not 0");
            assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "in P2P supplier not expected");
        }

        {
            Vars memory oldVars;
            Vars memory newVars;

            (, oldVars.BP2PD, , oldVars.BP2PA) = morpho.deltas(cDai);
            oldVars.NVD = ICToken(cDai).borrowIndex();
            oldVars.BP2PER = morpho.p2pBorrowIndex(cDai);
            (, oldVars.BPY) = getApproxBPYs(cDai);

            move1000BlocksForward(cDai);

            (, newVars.BP2PD, , newVars.BP2PA) = morpho.deltas(cDai);
            newVars.NVD = ICToken(cDai).borrowIndex();
            newVars.BP2PER = morpho.p2pBorrowIndex(cDai);
            (, newVars.BPY) = getApproxBPYs(cDai);
            newVars.LR = ICToken(cDai).supplyRatePerBlock();
            newVars.VBR = ICToken(cDai).borrowRatePerBlock();

            uint256 shareOfTheDelta = newVars.BP2PD.mul(newVars.NVD).div(oldVars.BP2PER).div(
                newVars.BP2PA
            );

            uint256 expectedBP2PER = oldVars.BP2PER.mul(
                _computeCompoundedInterest(oldVars.BPY, 1000).mul(WAD - shareOfTheDelta) +
                    shareOfTheDelta.mul(newVars.NVD).div(oldVars.NVD)
            );

            assertApproxEq(
                expectedBP2PER,
                newVars.BP2PER,
                (expectedBP2PER * 2) / 100,
                "BP2PER not expected"
            );

            uint256 expectedBorrowBalanceInUnderlying = borrowedAmount.div(oldVars.BP2PER).mul(
                expectedBP2PER
            );

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
                    cDai,
                    address(borrowers[i])
                );
                assertApproxEq(
                    inP2PBorrower.mul(newVars.BP2PER),
                    expectedBorrowBalanceInUnderlying,
                    (expectedBorrowBalanceInUnderlying * 2) / 100,
                    "not expected underlying balance"
                );
                assertEq(onPoolBorrower, 0);
            }
        }

        // Borrow delta reduction with borrowers repaying
        for (uint256 i = 10; i < 20; i++) {
            borrowers[i].approve(dai, borrowedAmount);
            borrowers[i].repay(cDai, borrowedAmount);
        }

        (, uint256 p2pBorrowDeltaAfter, , ) = morpho.deltas(cDai);
        assertApproxEq(p2pBorrowDeltaAfter, 0, 1, "borrow Delta 2");

        (uint256 inP2PSupplier2, uint256 onPoolSupplier2) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier2)
        );

        assertEq(inP2PSupplier2, expectedSupplyBalanceInP2P);
        assertEq(onPoolSupplier2, 0);
    }

    function testDeltaWithdrawAll() public {
        // 1.3e6 allows only 10 unmatch borrowers.
        setMaxGasForMatchingHelper(3e6, 3e6, 3.2e6, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount + 7;

        // supplier1 and 20 borrowers are matched for suppliedAmount.
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        createSigners(20);

        // 2 * NMAX borrowers borrow borrowedAmount.
        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, borrowedAmount, type(uint64).max);
        }

        // Supplier withdraws max.
        // Should create a delta on borrowers side.
        supplier1.withdraw(cDai, type(uint256).max);

        move1000BlocksForward(cDai);

        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(dai, type(uint256).max);
            borrowers[i].repay(cDai, type(uint256).max);
            borrowers[i].withdraw(cUsdc, type(uint256).max);
        }
    }

    function testShouldNotWithdrawWhenUnderCollaterized() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = toSupply / 2;

        // supplier1 deposits collateral.
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        // supplier2 deposits collateral.
        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        // supplier1 tries to withdraw more than allowed.
        supplier1.borrow(cUsdc, to6Decimals(toBorrow));
        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        supplier1.withdraw(cDai, toSupply);
    }

    // Test attack.
    // Should be possible to withdraw amount while an attacker sends cToken to trick Morpho contract.
    function testWithdrawWhileAttackerSendsCToken() public {
        Attacker attacker = new Attacker();
        tip(dai, address(attacker), type(uint256).max / 2);

        uint256 toSupply = 100 ether;
        uint256 collateral = 2 * toSupply;
        uint256 toBorrow = toSupply;

        // Attacker sends cToken to morpho contract.
        attacker.approve(dai, cDai, toSupply);
        attacker.deposit(cDai, toSupply);
        attacker.transfer(dai, address(morpho), toSupply);

        // supplier1 deposits collateral.
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        // borrower1 deposits collateral.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        // supplier1 tries to withdraw.
        borrower1.borrow(cDai, toBorrow);
        supplier1.withdraw(cDai, toSupply);
    }

    function testFailWithdrawZero() public {
        morpho.withdraw(cDai, 0);
    }

    function testWithdrawnOnPoolThreshold() public {
        uint256 amountWithdrawn = 1e6;

        supplier1.approve(dai, 1 ether);
        supplier1.supply(cDai, 1 ether);

        hevm.expectRevert(abi.encodeWithSignature("WithdrawTooSmall()"));
        supplier1.withdraw(cDai, amountWithdrawn);
    }
}
