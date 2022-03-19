// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    // 1.1 - There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.
    function test_supply_1_1() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = underlyingToPoolSupplyBalance(amount, supplyPoolIndex);

        assertApproxEq(
            poolSupplyBalanceToUnderlying(
                IERC20(cDai).balanceOf(address(positionsManager)),
                supplyPoolIndex
            ),
            amount,
            1e9,
            "balance of cToken"
        );

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        testEquality(onPool, expectedOnPool, "on pool");
        testEquality(inP2P, 0, "in P2P");
    }

    // Should be able to supply more ERC20 after already having supply ERC20
    function test_supply_multiple() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(cDai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = underlyingToPoolSupplyBalance(2 * amount, supplyPoolIndex);

        (, uint256 onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    // 1.2 - There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.
    function test_supply_1_2() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        uint256 daiBalanceBefore = supplier1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - amount;

        supplier1.approve(dai, address(positionsManager), amount);
        supplier1.supply(cDai, amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(dai);
        testEquality(daiBalanceAfter, expectedDaiBalanceAfter);

        uint256 supplyP2PExchangeRate = marketsManager.getUpdatedSupplyP2PExchangeRate(cDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(amount, supplyP2PExchangeRate);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);

        testEquality(onPoolBorrower, 0);
        testEquality(inP2PBorrower, inP2PSupplier);
    }

    // 1.3 - There is 1 available borrower, he doesn't match 100% of the supplier liquidity.
    // Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.
    function test_supply_1_3() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, 2 * amount);

        uint256 supplyP2PExchangeRate = marketsManager.getUpdatedSupplyP2PExchangeRate(cDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(amount, supplyP2PExchangeRate);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedSupplyBalanceOnPool = underlyingToPoolSupplyBalance(
            amount,
            supplyPoolIndex
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool);
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PBorrower, inP2PSupplier);
    }

    // 1.4 - There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.
    function test_supply_1_4() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
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
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrowers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower, "amount per borrower");
            testEquality(onPool, 0, "on pool per borrower");
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        expectedInP2P = p2pUnitToUnderlying(amount, supplyP2PExchangeRate);

        assertApproxEq(inP2P, expectedInP2P, 1e3, "in P2P");
        testEquality(onPool, 0, "on pool");
    }

    // 1.5 - The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`.
    // ⚠️ most gas expensive supply scenario.
    function test_supply_1_5() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
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
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrowers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));

        expectedInP2P = p2pUnitToUnderlying(amount / 2, supplyP2PExchangeRate);
        uint256 expectedOnPool = underlyingToPoolSupplyBalance(amount / 2, supplyPoolIndex);

        assertApproxEq(inP2P, expectedInP2P, 1e3, "in P2P");
        testEquality(onPool, expectedOnPool, "in pool");
    }
}
