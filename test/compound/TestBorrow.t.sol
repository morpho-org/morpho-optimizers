// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    using CompoundMath for uint256;

    // The borrower tries to borrow more than his collateral allows, the transaction reverts.
    function testBorrow1() public {
        uint256 usdcAmount = to6Decimals(10_000 ether);

        borrower1.approve(usdc, usdcAmount);
        borrower1.supply(cUsdc, usdcAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        hevm.expectRevert(PositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(cDai, borrowable + 1e12);
    }

    // There are no available suppliers: all of the borrowed amount is `onPool`.
    function testBorrow2() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedOnPool = amount.div(ICToken(cDai).borrowIndex());

        testEquality(onPool, expectedOnPool);
        assertEq(inP2P, 0);
    }

    // There is 1 available supplier, he matches 100% of the borrower liquidity, everything is `inP2P`.
    function testBorrow3() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(amount * 2));
        borrower1.supply(cUsdc, to6Decimals(amount * 2));

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        (, uint256 supplyOnPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        uint256 toBorrow = supplyOnPool.mul(cDaiSupplyIndex);
        borrower1.borrow(cDai, toBorrow);

        (uint256 supplyInP2P, ) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
        uint256 expectedSupplyInP2P = getBalanceOnCompound(amount, cDaiSupplyIndex).div(
            p2pSupplyIndex
        );
        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiSupplyIndex).div(
            p2pBorrowIndex
        );

        testEquality(supplyInP2P, expectedSupplyInP2P, "Supplier1 in peer-to-peer");

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        assertEq(onPool, 0, "Borrower1 on pool");
        testEquality(inP2P, expectedBorrowInP2P, "Borrower1 in peer-to-peer");
    }

    // There is 1 available supplier, he doesn't match 100% of the borrower liquidity. Borrower `inP2P` is equal to the supplier previous amount `onPool`, the rest is set `onPool`.
    function testBorrow4() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));
        uint256 borrowAmount = amount * 2;

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, borrowAmount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiSupplyIndex).div(
            morpho.p2pBorrowIndex(cDai)
        );
        uint256 expectedBorrowOnPool = (borrowAmount -
            getBalanceOnCompound(amount, cDaiSupplyIndex))
        .div(ICToken(cDai).borrowIndex());

        testEquality(inP2P, expectedBorrowInP2P, "Borrower1 in peer-to-peer");
        testEquality(onPool, expectedBorrowOnPool, "Borrower1 on pool");
    }

    // There are NMAX (or less) supplier that match the borrowed amount, everything is `inP2P` after NMAX (or less) match.
    function testBorrow5() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 5;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / NMAX;
        uint256[] memory rates = new uint256[](NMAX);
        uint256 toBorrow;

        for (uint256 i = 0; i < NMAX; i++) {
            // Rates change every time.
            rates[i] = ICToken(cDai).exchangeRateCurrent();
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);

            (, uint256 supplyOnPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
            toBorrow += supplyOnPool.mul(rates[i]);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, toBorrow);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 inP2P;
        uint256 onPool;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));

            testEquality(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(p2pSupplyIndex),
                "in peer-to-peer"
            );
            assertEq(onPool, 0, "on pool");
        }

        (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiSupplyIndex).div(
            morpho.p2pBorrowIndex(cDai)
        );

        testEquality(inP2P, expectedBorrowInP2P, "Borrower1 in peer-to-peer");
        assertEq(onPool, 0);
    }

    // The NMAX biggest supplier don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set `onPool`. ⚠️ most gas expensive borrow scenario.
    function testBorrow6() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 5;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / (2 * NMAX);
        uint256[] memory rates = new uint256[](NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            // Rates change every time.
            rates[i] = ICToken(cDai).exchangeRateCurrent();
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 matchedAmount;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));

            testEquality(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(morpho.p2pSupplyIndex(cDai)),
                "in peer-to-peer"
            );
            assertEq(onPool, 0, "on pool");

            matchedAmount += getBalanceOnCompound(amountPerSupplier, cDaiSupplyIndex);
        }

        (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount / 2, cDaiSupplyIndex).div(
            morpho.p2pBorrowIndex(cDai)
        );
        uint256 expectedBorrowOnPool = (amount - matchedAmount).div(borrowIndex);

        testEquality(inP2P, expectedBorrowInP2P, "Borrower1 in peer-to-peer");
        testEquality(onPool, expectedBorrowOnPool, "Borrower1 on pool");
    }

    function testBorrowMultipleAssets() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, address(morpho), to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));

        borrower1.borrow(cDai, amount);
        borrower1.borrow(cDai, amount);

        (, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedOnPool = (2 * amount).div(ICToken(cDai).borrowIndex());
        testEquality(onPool, expectedOnPool);
    }

    function testShouldNotBorrowZero() public {
        hevm.expectRevert(PositionsManager.AmountIsZero.selector);
        morpho.borrow(cDai, 0, type(uint256).max);
    }

    function testBorrowOnPoolThreshold() public {
        uint256 amountBorrowed = 1;

        borrower1.approve(usdc, to6Decimals(1 ether));
        borrower1.supply(cUsdc, to6Decimals(1 ether));

        // We check that borrowing any amount accrue the debt.
        borrower1.borrow(cDai, amountBorrowed);
        (, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        testEquality(onPool, ICToken(cDai).balanceOf(address(morpho)));
        testEquality(
            ICToken(cDai).borrowBalanceCurrent(address(morpho)),
            amountBorrowed,
            "borrow balance"
        );
    }

    function testBorrowLargerThanDeltaShouldClearDelta() public {
        // Allows only 10 unmatch suppliers.

        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 20 * suppliedAmount;
        uint256 collateral = 100 * borrowedAmount;

        // borrower1 and 20 suppliers are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        createSigners(20);

        // 2 * NMAX suppliers supply suppliedAmount.
        for (uint256 i = 0; i < 20; i++) {
            suppliers[i].approve(dai, suppliedAmount);
            suppliers[i].supply(cDai, suppliedAmount);
        }

        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);

        vm.roll(block.number + 1);
        // Delta should be created.
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        vm.roll(block.number + 1);
        (uint256 p2pSupplyDeltaBefore, , , ) = morpho.deltas(cDai);
        borrower1.borrow(cDai, borrowedAmount * 2);
        (uint256 p2pSupplyDeltaAfter, , , ) = morpho.deltas(cDai);

        assertGt(p2pSupplyDeltaBefore, 0);
        assertEq(p2pSupplyDeltaAfter, 0);
    }

    function testShouldMatchBorrowWithCorrectAmountOfGas() public {
        uint256 amount = 100 ether;
        createSigners(30);

        uint256 snapshotId = vm.snapshot();
        uint256 gasUsed1 = _getBorrowGasUsage(amount, 1e5);

        vm.revertTo(snapshotId);
        uint256 gasUsed2 = _getBorrowGasUsage(amount, 2e5);

        assertGt(gasUsed2, gasUsed1 + 5e4);
    }

    /// @dev Helper for gas usage test
    function _getBorrowGasUsage(uint256 amount, uint256 maxGas) internal returns (uint256 gasUsed) {
        // 2 * NMAX suppliers supply amount
        for (uint256 i; i < 30; i++) {
            suppliers[i].approve(dai, type(uint256).max);
            suppliers[i].supply(cDai, amount);
        }

        borrower1.approve(usdc, to6Decimals(amount * 200));
        borrower1.supply(cUsdc, to6Decimals(amount * 200));

        uint256 gasLeftBefore = gasleft();
        borrower1.borrow(cDai, amount * 20, maxGas);

        gasUsed = gasLeftBefore - gasleft();
    }
}
