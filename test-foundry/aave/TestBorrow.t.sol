// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    function testBorrow1() public {
        uint256 usdcAmount = to6Decimals(10_000 ether);

        borrower1.approve(usdc, usdcAmount);
        borrower1.supply(aUsdc, usdcAmount);

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.borrow(aDai, borrowable + 1e12);
    }

    function testBorrow2() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedOnPool = underlyingToAdUnit(amount, normalizedVariableDebt);

        testEquality(onPool, expectedOnPool);
        testEquality(inP2P, 0);
    }

    function testBorrow3() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(usdc, to6Decimals(amount * 2));
        borrower1.supply(aUsdc, to6Decimals(amount * 2));
        borrower1.borrow(aDai, amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 expectedInP2P = p2pUnitToUnderlying(supplyInP2P, borrowP2PExchangeRate);

        testEquality(expectedInP2P, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        testEquality(onPool, 0);
        testEquality(inP2P, supplyInP2P);
    }

    function testBorrow4() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(usdc, to6Decimals(4 * amount));
        borrower1.supply(aUsdc, to6Decimals(4 * amount));
        uint256 borrowAmount = amount * 2;
        borrower1.borrow(aDai, borrowAmount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        testEquality(inP2P, supplyInP2P);

        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedOnPool = underlyingToAdUnit(amount, normalizedVariableDebt);

        testEquality(onPool, expectedOnPool);
    }

    function testBorrow5() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
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
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(inP2P, amount);
        testEquality(onPool, 0);
    }

    function testBorrow6() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
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
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        expectedInP2P = p2pUnitToUnderlying(amount / 2, supplyP2PExchangeRate);
        uint256 expectedOnPool = underlyingToAdUnit(amount / 2, normalizedVariableDebt);

        testEquality(inP2P, expectedInP2P);
        testEquality(onPool, expectedOnPool);
    }

    function testBorrowMultipleAssets() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(4 * amount));
        borrower1.supply(aUsdc, to6Decimals(4 * amount));

        borrower1.borrow(aDai, amount);
        borrower1.borrow(aDai, amount);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedOnPool = underlyingToAdUnit(2 * amount, normalizedVariableDebt);
        testEquality(onPool, expectedOnPool);
    }

    function testFailBorrowZero() public {
        positionsManager.borrow(aDai, 0, 1, type(uint256).max);
    }

    function testBorrowUpdateIndexesSameAsCompound() public {
        uint256 collateral = 1 ether;
        uint256 borrow = collateral / 10;

        supplier1.approve(dai, type(uint256).max);
        supplier1.approve(usdc, type(uint256).max);

        supplier1.supply(cDai, collateral);
        supplier1.supply(cUsdc, to6Decimals(collateral));

        supplier1.borrow(cBat, borrow);
        supplier1.borrow(cUsdt, to6Decimals(borrow));

        uint256 daiP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cDai);
        uint256 daiP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cDai);
        uint256 usdcP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cUsdc);
        uint256 usdcP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cUsdc);
        uint256 batP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cBat);
        uint256 batP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cBat);
        uint256 usdtP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cUsdt);
        uint256 usdtP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cUsdt);

        hevm.roll(block.number + 1);

        supplier1.borrow(cBat, borrow);

        uint256 daiP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cDai);
        uint256 daiP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cDai);
        uint256 usdcP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cUsdc);
        uint256 usdcP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cUsdc);
        uint256 batP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cBat);
        uint256 batP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cBat);
        uint256 usdtP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cUsdt);
        uint256 usdtP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cUsdt);

        assertEq(daiP2PBorrowIndexAfter, daiP2PSupplyIndexBefore);
        assertEq(daiP2PSupplyIndexAfter, daiP2PBorrowIndexBefore);
        assertEq(usdcP2PSupplyIndexAfter, usdcP2PSupplyIndexBefore);
        assertEq(usdcP2PBorrowIndexAfter, usdcP2PBorrowIndexBefore);
        assertEq(batP2PSupplyIndexAfter, batP2PSupplyIndexBefore);
        assertEq(batP2PBorrowIndexAfter, batP2PBorrowIndexBefore);
        assertGt(usdtP2PSupplyIndexAfter, usdtP2PSupplyIndexBefore);
        assertGt(usdtP2PBorrowIndexAfter, usdtP2PBorrowIndexBefore);

        supplier1.compoundSupply(cDai, collateral);
        supplier1.compoundSupply(cUsdc, to6Decimals(collateral));

        supplier1.compoundBorrow(cBat, borrow);
        supplier1.compoundBorrow(cUsdt, to6Decimals(borrow));

        uint256 daiPoolSupplyIndexBefore = ICToken(cDai).exchangeRateStored();
        uint256 daiPoolBorrowIndexBefore = ICToken(cDai).borrowIndex();
        uint256 usdcPoolSupplyIndexBefore = ICToken(cUsdc).exchangeRateStored();
        uint256 usdcPoolBorrowIndexBefore = ICToken(cUsdc).borrowIndex();
        uint256 batPoolSupplyIndexBefore = ICToken(cBat).exchangeRateStored();
        uint256 batPoolBorrowIndexBefore = ICToken(cBat).borrowIndex();
        uint256 usdtPoolSupplyIndexBefore = ICToken(cUsdt).exchangeRateStored();
        uint256 usdtPoolBorrowIndexBefore = ICToken(cUsdt).borrowIndex();

        hevm.roll(block.number + 1);

        supplier1.compoundBorrow(cBat, borrow);

        uint256 daiPoolSupplyIndexAfter = ICToken(cDai).exchangeRateStored();
        uint256 daiPoolBorrowIndexAfter = ICToken(cDai).borrowIndex();
        uint256 usdcPoolSupplyIndexAfter = ICToken(cUsdc).exchangeRateStored();
        uint256 usdcPoolBorrowIndexAfter = ICToken(cUsdc).borrowIndex();
        uint256 batPoolSupplyIndexAfter = ICToken(cBat).exchangeRateStored();
        uint256 batPoolBorrowIndexAfter = ICToken(cBat).borrowIndex();
        uint256 usdtPoolSupplyIndexAfter = ICToken(cUsdt).exchangeRateStored();
        uint256 usdtPoolBorrowIndexAfter = ICToken(cUsdt).borrowIndex();

        assertEq(daiPoolBorrowIndexAfter, daiPoolSupplyIndexBefore);
        assertEq(daiPoolSupplyIndexAfter, daiPoolBorrowIndexBefore);
        assertEq(usdcPoolSupplyIndexAfter, usdcPoolSupplyIndexBefore);
        assertEq(usdcPoolBorrowIndexAfter, usdcPoolBorrowIndexBefore);
        assertEq(batPoolSupplyIndexAfter, batPoolSupplyIndexBefore);
        assertEq(batPoolBorrowIndexAfter, batPoolBorrowIndexBefore);
        assertGt(usdtPoolSupplyIndexAfter, usdtPoolSupplyIndexBefore);
        assertGt(usdtPoolBorrowIndexAfter, usdtPoolBorrowIndexBefore);
    }
}
