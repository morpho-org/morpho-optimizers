// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using stdStorage for StdStorage;
    using WadRayMath for uint256;

    // There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.
    function testSupply1() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 expectedOnPool = amount.rayDiv(pool.getReserveNormalizedIncome(dai));

        assertEq(IERC20(aDai).balanceOf(address(morpho)), amount);

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        assertEq(onPool, expectedOnPool);
        assertEq(inP2P, 0);
    }

    // There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.
    function testSupply2() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 daiBalanceBefore = supplier1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - amount;

        supplier1.approve(dai, address(morpho), amount);
        supplier1.supply(aDai, amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(dai);

        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedSupplyBalanceInP2P = amount.rayDiv(p2pSupplyIndex);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(onPoolSupplier, 0);
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P);

        assertEq(onPoolBorrower, 0);
        assertEq(inP2PBorrower, inP2PSupplier);
    }

    // There is 1 available borrower, he doesn't match 100% of the supplier liquidity. Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.
    function testSupply3() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(aDai, 2 * amount);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedSupplyBalanceInP2P = amount.rayDiv(p2pSupplyIndex);

        uint256 normalizedIncome = pool.getReserveNormalizedIncome(dai);
        uint256 expectedSupplyBalanceOnPool = amount.rayDiv(normalizedIncome);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        assertEq(onPoolSupplier, expectedSupplyBalanceOnPool);
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P);

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        assertEq(onPoolBorrower, 0);
        assertEq(inP2PBorrower, inP2PSupplier);
    }

    // There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.
    function testSupply4() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = amount / NMAX;

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 inP2PInUnderlying;
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        for (uint256 i; i < NMAX; i++) {
            (inP2P, onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));
            inP2PInUnderlying = inP2P.rayMul(p2pSupplyIndex);

            assertEq(inP2PInUnderlying, amountPerBorrower, "amount per borrower");
            assertEq(onPool, 0, "on pool per borrower");
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        uint256 expectedInP2P = amount.rayDiv(morpho.p2pBorrowIndex(aDai));

        assertEq(inP2P, expectedInP2P);
        assertEq(onPool, 0);
    }

    // The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`. ⚠️ most gas expensive supply scenario.
    function testSupply5() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = amount / (2 * NMAX);

        for (uint256 i; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 inP2PInUnderlying;
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 normalizedIncome = pool.getReserveNormalizedIncome(dai);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));
            inP2PInUnderlying = inP2P.rayMul(p2pBorrowIndex);

            assertEq(inP2PInUnderlying, amountPerBorrower, "borrower in peer-to-peer");
            assertEq(onPool, 0);
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        uint256 expectedInP2P = (amount / 2).rayDiv(morpho.p2pSupplyIndex(aDai));
        uint256 expectedOnPool = (amount / 2).rayDiv(normalizedIncome);

        assertEq(inP2P, expectedInP2P, "in peer-to-peer");
        assertEq(onPool, expectedOnPool, "in pool");
    }

    function testSupplyMultipleTimes() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(aDai, amount);
        supplier1.supply(aDai, amount);

        uint256 expectedOnPool = (2 * amount).rayDiv(pool.getReserveNormalizedIncome(dai));

        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(onPool, expectedOnPool);
    }

    function testShouldNotSupplyZero() public {
        hevm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
        morpho.supply(aDai, msg.sender, 0, type(uint256).max);
    }

    function testSupplyRepayOnBehalf() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        // Someone repays on behalf of Morpho.
        supplier2.approve(dai, address(pool), amount);
        hevm.prank(address(supplier2));
        pool.repay(dai, amount, 2, address(morpho));

        // Supplier 1 supply in peer-to-peer. Not supposed to revert.
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);
    }

    function testSupplyOnBehalf() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        hevm.prank(address(supplier1));
        morpho.supply(aDai, address(supplier2), amount);

        uint256 expectedOnPool = amount.rayDiv(pool.getReserveNormalizedIncome(dai));

        assertEq(ERC20(aDai).balanceOf(address(morpho)), amount, "balance of aToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier2));

        assertApproxEqAbs(onPool, expectedOnPool, 1, "on pool");
        assertEq(inP2P, 0, "in peer-to-peer");
    }

    function testSupplyAfterFlashloan() public {
        uint256 amount = 1_000 ether;
        uint256 flashLoanAmount = 10_000 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);

        FlashLoan flashLoan = new FlashLoan(pool);
        vm.prank(address(supplier2));
        ERC20(dai).transfer(address(flashLoan), 10_000 ether); // To pay the premium.
        flashLoan.callFlashLoan(dai, flashLoanAmount);

        vm.warp(block.timestamp + 1);
        supplier1.supply(aDai, amount);
    }

    function testShouldMatchSupplyWithCorrectAmountOfGas() public {
        uint256 amount = 100 ether;
        createSigners(30);

        uint256 snapshotId = vm.snapshot();
        uint256 gasUsed1 = _getSupplyGasUsage(amount, 1e5);

        vm.revertTo(snapshotId);
        uint256 gasUsed2 = _getSupplyGasUsage(amount, 2e5);

        assertGt(gasUsed2, gasUsed1 + 1e4);
    }

    /// @dev Helper for gas usage test
    function _getSupplyGasUsage(uint256 amount, uint256 maxGas) internal returns (uint256 gasUsed) {
        // 2 * NMAX borrowers borrow amount
        for (uint256 i; i < 30; i++) {
            borrowers[i].approve(usdc, type(uint256).max);
            borrowers[i].supply(aUsdc, to6Decimals(amount * 3));
            borrowers[i].borrow(aDai, amount);
        }

        supplier1.approve(dai, amount * 20);

        uint256 gasLeftBefore = gasleft();
        supplier1.supply(aDai, amount * 20, maxGas);

        gasUsed = gasLeftBefore - gasleft();
    }
}
