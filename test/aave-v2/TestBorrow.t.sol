// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    // The borrower tries to borrow more than his collateral allows, the transaction reverts.
    function testBorrow1() public {
        uint256 usdcAmount = to6Decimals(10_000 ether);

        borrower1.approve(usdc, usdcAmount);
        borrower1.supply(aUsdc, usdcAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        hevm.expectRevert(EntryPositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(aDai, borrowable + 1e12);
    }

    // There are no available suppliers: all of the borrowed amount is `onPool`.
    function testBorrow2() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        uint256 expectedOnPool = amount.rayDiv(pool.getReserveNormalizedVariableDebt(dai));

        testEquality(onPool, expectedOnPool);
        testEquality(inP2P, 0);
    }

    // There is 1 available supplier, he matches 100% of the borrower liquidity, everything is `inP2P`.
    function testBorrow3() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(usdc, to6Decimals(amount * 2));
        borrower1.supply(aUsdc, to6Decimals(amount * 2));
        borrower1.borrow(aDai, amount);

        (uint256 supplyInP2P, ) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 expectedInP2PInUnderlying = supplyInP2P.rayMul(p2pBorrowIndex);

        testEquality(amount, expectedInP2PInUnderlying);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(onPool, 0);
        testEquality(inP2P, supplyInP2P);
    }

    // There is 1 available supplier, he doesn't match 100% of the borrower liquidity. Borrower `inP2P` is equal to the supplier previous amount `onPool`, the rest is set `onPool`.
    function testBorrow4() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(usdc, to6Decimals(4 * amount));
        borrower1.supply(aUsdc, to6Decimals(4 * amount));
        uint256 borrowAmount = amount * 2;
        borrower1.borrow(aDai, borrowAmount);

        (uint256 supplyInP2P, ) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(inP2P, supplyInP2P, "in P2P");

        uint256 expectedOnPool = amount.rayDiv(pool.getReserveNormalizedVariableDebt(dai));

        testEquality(onPool, expectedOnPool, "on pool");
    }

    // There are NMAX (or less) supplier that match the borrowed amount, everything is `inP2P` after NMAX (or less) match.
    function testBorrow5() public {
        // TODO: fix this.
        deal(dai, address(morpho), 1 ether);

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

        uint256 amountPerSupplier = amount / NMAX;

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));

            expectedInP2P = inP2P.rayMul(p2pSupplyIndex);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(
            inP2P,
            amount.rayDiv(morpho.p2pBorrowIndex(aDai)),
            "Borrower1 in peer-to-peer"
        );
        testEquality(onPool, 0, "Borrower1 on pool");
    }

    // The NMAX biggest supplier don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set `onPool`. ⚠️ most gas expensive borrow scenario.
    function testBorrow6() public {
        // TODO: fix this.
        deal(dai, address(morpho), 1 ether);

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

        uint256 amountPerSupplier = amount / (2 * NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 normalizedVariableDebt = pool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));

            expectedInP2P = inP2P.rayMul(p2pSupplyIndex);

            testEquality(expectedInP2P, amountPerSupplier, "on pool");
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        expectedInP2P = (amount / 2).rayDiv(morpho.p2pBorrowIndex(aDai));
        uint256 expectedOnPool = (amount / 2).rayDiv(normalizedVariableDebt);

        testEquality(inP2P, expectedInP2P, "Borrower1 in peer-to-peer");
        testEquality(onPool, expectedOnPool, "Borrower1 on pool");
    }

    function testBorrowMultipleAssets() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, address(morpho), to6Decimals(4 * amount));
        borrower1.supply(aUsdc, to6Decimals(4 * amount));

        borrower1.borrow(aDai, amount);
        borrower1.borrow(aDai, amount);

        (, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        uint256 normalizedVariableDebt = pool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedOnPool = (2 * amount).rayDiv(normalizedVariableDebt);
        testEquality(onPool, expectedOnPool);
    }

    function testShouldNotBorrowZero() public {
        hevm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
        morpho.borrow(aDai, 0, type(uint256).max);
    }

    function testShouldNotBorrowAssetNotBorrowable() public {
        uint256 amount = 100 ether;

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, amount);

        hevm.expectRevert(EntryPositionsManager.BorrowingNotEnabled.selector);
        borrower1.borrow(aAave, amount / 2);
    }

    function testShouldNotAllowSmallBorrow() public {
        (uint256 ltv, , , , ) = pool.getConfiguration(dai).getParamsMemory();

        createAndSetCustomPriceOracle().setDirectPrice(dai, 1e8);

        uint256 amount = 1 ether;
        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, amount);

        hevm.expectRevert(EntryPositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(aDai, (amount * ltv) / 10_000 + 1e9);
    }

    function testShouldNotAllowUSDTCollateral() public {
        uint256 amount = 1e8;
        // Give morpho enough of a position size
        supplier1.approve(usdc, amount * 10);
        supplier1.supply(aUsdc, amount * 10);

        // Add large usdt supply
        borrower1.approve(usdt, type(uint256).max);
        borrower1.supply(aUsdt, amount * 10);

        hevm.expectRevert(EntryPositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(aUsdc, amount);
    }

    function testBorrowLargerThanDeltaShouldClearDelta() public {
        // Allows only 10 unmatch suppliers.

        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 19 * suppliedAmount;
        uint256 collateral = 99 * borrowedAmount;

        // borrower1 and 20 suppliers are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        createSigners(20);

        // 2 * NMAX suppliers supply suppliedAmount.
        for (uint256 i = 0; i < 20; i++) {
            suppliers[i].approve(dai, suppliedAmount);
            suppliers[i].supply(aDai, suppliedAmount);
        }

        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);

        vm.roll(block.number + 1);
        // Delta should be created.
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        vm.roll(block.number + 1);
        (uint256 p2pSupplyDeltaBefore, , , ) = morpho.deltas(aDai);
        borrower1.borrow(aDai, borrowedAmount * 2);
        (uint256 p2pSupplyDeltaAfter, , , ) = morpho.deltas(aDai);

        assertGt(p2pSupplyDeltaBefore, 0);
        assertEq(p2pSupplyDeltaAfter, 0);
    }

    function testShouldUseRightAmountOfGas() public {
        uint256 amount = 100 ether;
        createSigners(30);

        uint256 snapshotId = vm.snapshot();
        uint256 gasUsed1 = _getBorrowGasUsage(amount, 1e5);

        vm.revertTo(snapshotId);
        uint256 gasUsed2 = _getBorrowGasUsage(amount, 2e5);

        assertGt(gasUsed2, gasUsed1 + 1e4);
    }

    /// @dev Helper for gas usage test
    function _getBorrowGasUsage(uint256 amount, uint256 maxGas) internal returns (uint256 gasUsed) {
        // 2 * NMAX suppliers supply amount
        for (uint256 i; i < 30; i++) {
            suppliers[i].approve(dai, type(uint256).max);
            suppliers[i].supply(aDai, amount);
        }

        borrower1.approve(usdc, to6Decimals(amount * 200));
        borrower1.supply(aUsdc, to6Decimals(amount * 200));

        uint256 gasLeftBefore = gasleft();
        borrower1.borrow(aDai, amount * 20, maxGas);

        gasUsed = gasLeftBefore - gasleft();
    }
}
