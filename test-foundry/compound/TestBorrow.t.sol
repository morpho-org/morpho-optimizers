// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";
import "@contracts/compound/positions-manager-parts/PositionsManagerForCompoundEventsErrors.sol";

contract TestBorrow is TestSetup {
    function testBorrow1() public {
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

    function testBorrow2() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 expectedOnPool = underlyingToDebtUnit(amount, borrowIndex);

        testEquality(onPool, expectedOnPool);
        testEquality(inP2P, 0);
    }

    function testBorrow3() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(amount * 2));
        borrower1.supply(cUsdc, to6Decimals(amount * 2));
        borrower1.borrow(cDai, amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
        uint256 expectedInP2P = underlyingToP2PUnit(amount, borrowP2PExchangeRate);

        testEquality(supplyInP2P, expectedInP2P);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        testEquality(onPool, 0, "Borrower1 on pool");
        testEquality(inP2P, supplyInP2P, "Borrower1 in P2P");
    }

    function testBorrow4() public {
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

        uint256 normalizedVariableDebt = ICToken(cDai).borrowIndex();
        uint256 expectedOnPool = (amount * 1e18)/normalizedVariableDebt;

        testEquality(onPool, expectedOnPool);
    }

    function testBorrow5() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 5;
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
        uint256 supplyP2PExchangeRate = ICToken(cDai).exchangeRateStored();
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        testEquality(inP2P, amount);
        testEquality(onPool, 0);
    }

    function testBorrow6() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 5;
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
        uint256 supplyP2PExchangeRate = ICToken(cDai).exchangeRateStored();
        uint256 normalizedVariableDebt = ICToken(cDai).borrowIndex();
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        expectedInP2P = p2pUnitToUnderlying(amount / 2, supplyP2PExchangeRate);
        uint256 expectedOnPool = underlyingToDebtUnit(amount / 2, normalizedVariableDebt);

        testEquality(inP2P, expectedInP2P);
        testEquality(onPool, expectedOnPool);
    }

    // Should be able to borrow more ERC20 after already having borrowed ERC20
    function testBorrowMultipleAssets() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));

        borrower1.borrow(cDai, amount);
        borrower1.borrow(cDai, amount);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 expectedOnPool = underlyingToDebtUnit(2 * amount, borrowIndex);
        testEquality(onPool, expectedOnPool);
    }
}
