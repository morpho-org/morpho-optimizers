// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";
import "@contracts/compound/positions-manager-parts/PositionsManagerForCompoundEventsErrors.sol";

contract TestBorrow is TestSetup {
    // 2.1 - The borrower tries to borrow more than what his collateral allows, the transaction reverts.
    function test_borrow_2_1() public {
        uint256 usdcAmount = to6Decimals(10_000 ether);

        borrower1.approve(usdc, usdcAmount);
        borrower1.supply(cUsdc, usdcAmount);

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        hevm.expectRevert(PositionsManagerForCompoundEventsErrors.DebtValueAboveMax.selector);
        borrower1.borrow(cDai, borrowable + 1e12);
    }

    // Should be able to borrow more ERC20 after already having borrowed ERC20
    function test_borrow_multiple() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));

        borrower1.borrow(cDai, amount);
        borrower1.borrow(cDai, amount);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 expectedOnPool = underlyingToCdUnit(2 * amount, borrowIndex);
        testEquality(onPool, expectedOnPool);
    }

    // 2.2 - There are no available suppliers: all of the borrowed amount is onPool.
    function test_borrow_2_2() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 expectedOnPool = underlyingToCdUnit(amount, borrowIndex);

        testEquality(onPool, expectedOnPool);
        testEquality(inP2P, 0);
    }

    // 2.3 - There is 1 available supplier, he matches 100% of the borrower liquidity, everything is inP2P.
    function test_borrow_2_3() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(amount * 2));
        borrower1.supply(cUsdc, to6Decimals(amount * 2));
        borrower1.borrow(cDai, amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
        uint256 expectedInP2P = underlyingToMUnit(amount, borrowP2PExchangeRate);

        testEquality(supplyInP2P, expectedInP2P);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        testEquality(onPool, 0, "Borrower1 on pool");
        testEquality(inP2P, supplyInP2P, "Borrower1 in P2P");
    }

    // 2.4 - There is 1 available supplier, he doesn't match 100% of the borrower liquidity.
    // Borrower inP2P is equal to the supplier previous amount onPool, the rest is set onPool.
    function test_borrow_2_4() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));
        uint256 borrowAmount = amount * 2;
        borrower1.borrow(cDai, borrowAmount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        testEquality(inP2P, supplyInP2P);

        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 expectedOnPool = underlyingToCdUnit(amount, borrowIndex);
        testEquality(onPool, expectedOnPool);
    }

    // 2.5 - There are NMAX (or less) suppliers that match the borrowed amount, everything is inP2P after NMAX (or less) match.
    function test_borrow_2_5() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / NMAX;

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));

            expectedInP2P = underlyingToMUnit(amountPerSupplier, supplyP2PExchangeRate);

            testEquality(inP2P, expectedInP2P);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        testEquality(inP2P, amount);
        testEquality(onPool, 0);
    }

    // 2.6 - The NMAX biggest suppliers don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set onPool.
    // ⚠️ most gas expensive borrow scenario.
    function test_borrow_2_6() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / (2 * NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));

            expectedInP2P = underlyingToMUnit(amountPerSupplier, supplyP2PExchangeRate);

            testEquality(inP2P, expectedInP2P);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        expectedInP2P = p2pUnitToUnderlying(amount / 2, supplyP2PExchangeRate);
        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 expectedOnPool = underlyingToCdUnit(amount / 2, borrowIndex);

        testEquality(inP2P, expectedInP2P);
        testEquality(onPool, expectedOnPool);
    }
}
