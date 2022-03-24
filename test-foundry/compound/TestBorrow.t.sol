// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

import "@contracts/compound/positions-manager-parts/PositionsManagerForCompoundEventsErrors.sol";
import "@contracts/compound/libraries/CompoundMath.sol";

contract TestBorrow is TestSetup {
    using CompoundMath for uint256;

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

        (uint256 supplyInP2P, uint256 supplyOnPool) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        console.log("in p2p units  ", supplyInP2P);
        console.log("in underlyings", supplyInP2P.mul(marketsManager.supplyP2PExchangeRate(cDai)));
        console.log("p2p exchange rate", marketsManager.supplyP2PExchangeRate(cDai));

        testEquality(
            supplyInP2P.mul(marketsManager.supplyP2PExchangeRate(cDai)),
            getBalanceOnCompound(amount, ICToken(cDai).exchangeRateStored()),
            "Supplier1 inP2P"
        );
        testEquality(supplyOnPool, 0, "Supplier1 on pool");

        (uint256 borrowInP2P, uint256 borrowOnPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 dustNotMatched = amount -
            supplyInP2P.mul(marketsManager.supplyP2PExchangeRate(cDai));

        testEquality(
            borrowOnPool,
            getBalanceOnCompound(dustNotMatched, ICToken(cDai).borrowIndex()),
            "Borrower1 on pool"
        );

        testEquality(borrowInP2P, supplyInP2P, "Borrower1 in P2P");
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

        testEquality(inP2P, supplyInP2P, "inP2P");

        uint256 dustNotMatched = amount - inP2P.mul(marketsManager.supplyP2PExchangeRate(cDai));

        testEquality(
            onPool.mul(ICToken(cDai).borrowIndex()),
            getBalanceOnCompound(amount + dustNotMatched, ICToken(cDai).borrowIndex()),
            "onPool"
        );
    }

    function testBorrow5() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 numberOfSupplier = 5;
        createSigners(numberOfSupplier);

        uint256 amountPerSupplier = amount / numberOfSupplier;

        for (uint256 i = 0; i < numberOfSupplier; i++) {
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 amountSuppliedOnComp = getBalanceOnCompound(
            amountPerSupplier,
            ICToken(cDai).exchangeRateStored()
        );
        uint256 dustNotMatched;

        for (uint256 i = 0; i < numberOfSupplier; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));

            testEquality(
                inP2P.mul(marketsManager.supplyP2PExchangeRate(cDai)),
                amountSuppliedOnComp,
                "P2P per Supplier"
            );
            testEquality(onPool, 0, "onPool per Supplier");

            dustNotMatched += amountPerSupplier - amountSuppliedOnComp;

            console.log("in p2p units             ", inP2P);
            console.log(
                "in underlyings           ",
                inP2P.mul(marketsManager.supplyP2PExchangeRate(cDai))
            );
            console.log("p2p exchange rate        ", marketsManager.supplyP2PExchangeRate(cDai));
            console.log("pool supply rate stored  ", ICToken(cDai).exchangeRateStored());
            console.log("pool borrow rate stored  ", ICToken(cDai).borrowIndex());
            console.log("===================");
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        testEquality(
            inP2P.mul(marketsManager.supplyP2PExchangeRate(cDai)),
            amount - dustNotMatched,
            "P2P for Borrower"
        );

        testEquality(
            onPool.mul(ICToken(cDai).exchangeRateStored()),
            getBalanceOnCompound(dustNotMatched, ICToken(cDai).exchangeRateStored()),
            "onPool for Borrower"
        );
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
