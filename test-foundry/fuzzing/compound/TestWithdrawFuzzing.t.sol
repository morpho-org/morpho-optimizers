// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";
import {Attacker} from "../../compound/helpers/Attacker.sol";

contract TestWithdraw is TestSetupFuzzing {
    using CompoundMath for uint256;

    function testWithdraw1(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        borrower1.borrow(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.withdraw(cUsdc, to6Decimals(collateral));
    }

    function testWithdraw2(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(cUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(2 * amount).div(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(inP2P, 0, "1: P2P not zero");
        assertEq(onPool, expectedOnPool, "1: OnPool not equal");

        supplier1.withdraw(cUsdc, to6Decimals(amount));

        (inP2P, onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        assertEq(inP2P, 0, "2: P2P not zero");
        assertApproxEq(onPool, expectedOnPool / 2, onPool / 1e8, "2: OnPool not equal");
    }

    function testWithdrawAll(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

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

    function testWithdraw3_1(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        uint256 borrowedAmount = amount;
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

        assertApproxEq(onPoolSupplier, expectedOnPool, 1, "1");
        assertEq(onPoolBorrower1, 0, "2");
        assertEq(inP2PSupplier, inP2PBorrower1, "3");

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(cDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(cDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPoolSupplier, 0, "4");
        assertApproxEq(inP2PSupplier, 0, 1, "5");

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier2));
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 expectedInP2P = (suppliedAmount / 2).div(p2pSupplyIndex);
        assertApproxEq(onPoolSupplier, expectedOnPool, 1, "6");
        assertApproxEq(inP2PSupplier, expectedInP2P, 1, "7");

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(cDai, address(borrower1));
        assertEq(onPoolBorrower1, 0, "8");
        assertApproxEq(inP2PSupplier, inP2PBorrower1, 1, "9");
    }

    function testWithdraw3_2(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        uint256 borrowedAmount = amount;
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

        assertEq(onPoolSupplier, expectedOnPool, "1");
        assertEq(onPoolBorrower, 0, "2");
        assertEq(inP2PSupplier, inP2PBorrower, "3");

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint8 NMAX = 20;
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
        assertEq(onPoolSupplier, 0, "4");
        assertApproxEq(inP2PSupplier, 0, 1, "5");

        // Check balances for the borrower.
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowBalanceInP2P = borrowedAmount.div(morpho.p2pSupplyIndex(cDai));

        assertApproxEq(
            inP2PBorrower,
            expectedBorrowBalanceInP2P,
            inP2PBorrower / 1e10,
            "borrower in P2P"
        );
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

    function testWithdraw3_3(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        uint256 borrowedAmount = amount;
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

        assertEq(onPoolSupplier, expectedOnPool, "1");
        assertEq(onPoolBorrower, 0, "2");
        assertEq(inP2PSupplier, inP2PBorrower, "3");

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

        assertApproxEq(
            inP2PBorrower,
            expectedBorrowBalanceInP2P,
            inP2PBorrower / 1e10,
            "borrower in P2P"
        );
        assertApproxEq(onPoolBorrower, expectedBorrowBalanceOnPool, 1e3, "borrower on Pool");

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 expectedSupplyBalanceInP2P = ((25 * suppliedAmount) / 100).div(p2pSupplyIndex);

        assertApproxEq(
            inP2PSupplier,
            expectedSupplyBalanceInP2P,
            inP2PSupplier / 1e10,
            "supplier in P2P"
        );
        assertEq(onPoolSupplier, 0, "supplier on Pool");
    }

    function testWithdraw3_4(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        uint256 borrowedAmount = amount;
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
        uint8 NMAX = 20;
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

            assertApproxEq(
                inP2PBorrower,
                expectedBorrowBalanceInP2P,
                inP2PBorrower / 1e10,
                "borrower in P2P 2"
            );
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

    function testShouldNotWithdrawWhenUnderCollaterized(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        uint256 toSupply = amount;
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
    function testWithdrawWhileAttackerSendsCToken(uint256 amount) public {
        hevm.assume(amount > 1e18 / 100 && amount < 1e18 * 50_000_000); // $0.01 to $50_000_000

        Attacker attacker = new Attacker();
        tip(dai, address(attacker), type(uint256).max / 2);

        uint256 toSupply = amount;
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
}
