// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using CompoundMath for uint256;

    // There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.
    function testSupply1() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(poolSupplyIndex);

        testEquality(ERC20(cDai).balanceOf(address(morpho)), expectedOnPool, "balance of cToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        testEquality(onPool, expectedOnPool, "on pool");
        assertEq(inP2P, 0, "in peer-to-peer");
    }

    // There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.
    function testSupply2() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        uint256 daiBalanceBefore = supplier1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - amount;

        supplier1.approve(dai, address(morpho), amount);
        supplier1.supply(cDai, amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(dai);
        testEquality(daiBalanceAfter, expectedDaiBalanceAfter);

        uint256 expectedSupplyBalanceInP2P = amount.div(morpho.p2pSupplyIndex(cDai));
        uint256 expectedBorrowBalanceInP2P = amount.div(morpho.p2pBorrowIndex(cDai));

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        assertEq(onPoolSupplier, 0, "supplier on pool");
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "supplier in P2P");

        assertEq(onPoolBorrower, 0, "borrower on pool");
        assertEq(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in P2P");
    }

    // There is 1 available borrower, he doesn't match 100% of the supplier liquidity. Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.
    function testSupply3() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, 2 * amount);

        uint256 expectedSupplyBalanceInP2P = amount.div(morpho.p2pSupplyIndex(cDai));
        uint256 expectedSupplyBalanceOnPool = amount.div(ICToken(cDai).exchangeRateCurrent());

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool, "on pool supplier");
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P, "in peer-to-peer supplier");

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedInP2P = amount.div(morpho.p2pBorrowIndex(cDai));

        assertEq(onPoolBorrower, 0, "on pool borrower");
        assertEq(inP2PBorrower, expectedInP2P, "in peer-to-peer borrower");
    }

    // There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.
    function testSupply4() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = amount / NMAX;

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));

            borrowers[i].borrow(cDai, amountPerBorrower);
        }

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 expectedInP2P;
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));

            expectedInP2P = amountPerBorrower.div(morpho.p2pBorrowIndex(cDai));

            testEquality(inP2P, expectedInP2P, "amount per borrower");
            assertEq(onPool, 0, "on pool per borrower");
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        expectedInP2P = amount.div(p2pSupplyIndex);

        testEquality(inP2P, expectedInP2P, "in peer-to-peer");
        assertEq(onPool, 0, "on pool");
    }

    // The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`. ⚠️ most gas expensive supply scenario.
    function testSupply5() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = amount / (2 * NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));

            borrowers[i].borrow(cDai, amountPerBorrower);
        }

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 expectedInP2P;
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));

            expectedInP2P = amountPerBorrower.div(morpho.p2pBorrowIndex(cDai));

            testEquality(inP2P, expectedInP2P, "borrower in peer-to-peer");
            assertEq(onPool, 0, "borrower on pool");
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        expectedInP2P = (amount / 2).div(p2pSupplyIndex);
        uint256 expectedOnPool = (amount / 2).div(poolSupplyIndex);

        testEquality(inP2P, expectedInP2P, "in peer-to-peer");
        testEquality(onPool, expectedOnPool, "in pool");
    }

    function testSupplyMultipleTimes() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(cDai, amount);
        supplier1.supply(cDai, amount);

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = (2 * amount).div(poolSupplyIndex);

        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    function testShouldNotSupplyZero() public {
        hevm.expectRevert(PositionsManager.AmountIsZero.selector);
        morpho.supply(cDai, msg.sender, 0, type(uint256).max);
    }

    function testSupplyRepayOnBehalf() public {
        uint256 amount = 1 ether;
        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        // Someone repays on behalf of the morpho.
        supplier2.approve(dai, cDai, amount);
        hevm.prank(address(supplier2));
        ICToken(cDai).repayBorrowBehalf(address(morpho), amount);

        // Supplier supplies in peer-to-peer. Not supposed to revert.
        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);
    }

    function testSupplyOnPoolThreshold() public {
        uint256 amountSupplied = 1e6;

        supplier1.approve(dai, amountSupplied);
        supplier1.supply(cDai, amountSupplied);

        // We check that supplying 0 in cToken units doesn't lead to a revert.
        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(ICToken(cDai).balanceOf(address(positionsManager)), 0, "balance of cToken");
        assertEq(onPool, 0, "Balance in Positions Manager");
    }

    function testSupplyOnBehalf() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        hevm.prank(address(supplier1));
        morpho.supply(cDai, address(supplier2), amount);

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(poolSupplyIndex);

        assertEq(ERC20(cDai).balanceOf(address(morpho)), expectedOnPool, "balance of cToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier2));

        assertEq(onPool, expectedOnPool, "on pool");
        assertEq(inP2P, 0, "in peer-to-peer");
    }

    function testSupplyUpdateIndexesSameAsCompound() public {
        uint256 amount = 1 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.approve(usdc, type(uint256).max);

        supplier1.supply(cDai, amount);
        supplier1.supply(cUsdc, to6Decimals(amount));

        uint256 daiP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cDai);
        uint256 daiP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cDai);
        uint256 usdcP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cUsdc);
        uint256 usdcP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cUsdc);

        hevm.roll(block.number + 1);

        supplier1.supply(cDai, amount);

        uint256 daiP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cDai);
        uint256 daiP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cDai);
        uint256 usdcP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cUsdc);
        uint256 usdcP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cUsdc);

        assertGt(daiP2PBorrowIndexAfter, daiP2PSupplyIndexBefore);
        assertGt(daiP2PSupplyIndexAfter, daiP2PBorrowIndexBefore);
        assertEq(usdcP2PSupplyIndexAfter, usdcP2PSupplyIndexBefore);
        assertEq(usdcP2PBorrowIndexAfter, usdcP2PBorrowIndexBefore);

        supplier1.compoundSupply(cDai, amount);
        supplier1.compoundSupply(cUsdc, to6Decimals(amount));

        uint256 daiPoolSupplyIndexBefore = ICToken(cDai).exchangeRateStored();
        uint256 daiPoolBorrowIndexBefore = ICToken(cDai).borrowIndex();
        uint256 usdcPoolSupplyIndexBefore = ICToken(cUsdc).exchangeRateStored();
        uint256 usdcPoolBorrowIndexBefore = ICToken(cUsdc).borrowIndex();

        hevm.roll(block.number + 1);

        supplier1.compoundSupply(cDai, amount);

        uint256 daiPoolSupplyIndexAfter = ICToken(cDai).exchangeRateStored();
        uint256 daiPoolBorrowIndexAfter = ICToken(cDai).borrowIndex();
        uint256 usdcPoolSupplyIndexAfter = ICToken(cUsdc).exchangeRateStored();
        uint256 usdcPoolBorrowIndexAfter = ICToken(cUsdc).borrowIndex();

        assertGt(daiPoolSupplyIndexAfter, daiPoolSupplyIndexBefore);
        assertGt(daiPoolBorrowIndexAfter, daiPoolBorrowIndexBefore);
        assertEq(usdcPoolSupplyIndexAfter, usdcPoolSupplyIndexBefore);
        assertEq(usdcPoolBorrowIndexAfter, usdcPoolBorrowIndexBefore);
    }

    function testShouldMatchSupplyWithCorrectAmountOfGas() public {
        uint256 amount = 100 ether;
        createSigners(30);

        uint256 snapshotId = vm.snapshot();
        uint256 gasUsed1 = _getSupplyGasUsage(amount, 1e5);

        vm.revertTo(snapshotId);
        uint256 gasUsed2 = _getSupplyGasUsage(amount, 2e5);

        assertGt(gasUsed2, gasUsed1 + 5e4);
    }

    function testPoolIndexGrowthInsideBlock() public {
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 1 ether);

        (, uint256 poolSupplyIndexCachedBefore, ) = morpho.lastPoolIndexes(cDai);

        vm.prank(address(supplier1));
        ERC20(dai).transfer(cDai, 10_000 ether);

        supplier1.supply(cDai, 1);

        (, uint256 poolSupplyIndexCachedAfter, ) = morpho.lastPoolIndexes(cDai);

        assertGt(poolSupplyIndexCachedAfter, poolSupplyIndexCachedBefore);
    }

    function testP2PIndexGrowthInsideBlock() public {
        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, 1 ether);
        borrower1.borrow(cDai, 0.5 ether);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        // Bypass the borrow repay in the same block by overwritting the storage slot lastBorrowBlock[borrower1].
        hevm.store(address(morpho), keccak256(abi.encode(address(borrower1), 178)), 0);
        // Create delta.
        borrower1.repay(cDai, type(uint256).max);

        uint256 p2pSupplyIndexBefore = morpho.p2pSupplyIndex(cDai);

        vm.prank(address(supplier1));
        ERC20(dai).transfer(cDai, 10_000 ether);

        borrower1.supply(cDai, 1);

        uint256 p2pSupplyIndexAfter = morpho.p2pSupplyIndex(cDai);

        assertGt(p2pSupplyIndexAfter, p2pSupplyIndexBefore);
    }

    /// @dev Helper for gas usage test
    function _getSupplyGasUsage(uint256 amount, uint256 maxGas) internal returns (uint256 gasUsed) {
        // 2 * NMAX borrowers borrow amount
        for (uint256 i; i < 30; i++) {
            borrowers[i].approve(usdc, type(uint256).max);
            borrowers[i].supply(cUsdc, to6Decimals(amount * 3));
            borrowers[i].borrow(cDai, amount);
        }

        supplier1.approve(dai, amount * 20);

        uint256 gasLeftBefore = gasleft();
        supplier1.supply(cDai, amount * 20, maxGas);

        gasUsed = gasLeftBefore - gasleft();
    }
}
