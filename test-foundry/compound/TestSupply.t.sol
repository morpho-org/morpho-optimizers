// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using CompoundMath for uint256;

    function testSupply1() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(supplyPoolIndex);

        assertApproxEq(
            IERC20(cDai).balanceOf(address(positionsManager)).mul(supplyPoolIndex),
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

    function testSupply2() public {
        uint256 amount = 10_000 ether;

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
        uint256 expectedSupplyBalanceInP2P = amount.div(supplyP2PExchangeRate);

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

    function testSupply3() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, 2 * amount);

        uint256 supplyP2PExchangeRate = marketsManager.getUpdatedSupplyP2PExchangeRate(cDai);
        uint256 expectedSupplyBalanceInP2P = amount.div(supplyP2PExchangeRate);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedSupplyBalanceOnPool = amount.div(supplyPoolIndex);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool, "on pool supplier");
        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P, "in P2P supplier");

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower, 0, "on pool borrower");
        testEquality(inP2PBorrower, inP2PSupplier, "in P2P borrower");
    }

    function testSupply4() public {
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

            expectedInP2P = inP2P.mul(supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower, "amount per borrower");
            testEquality(onPool, 0, "on pool per borrower");
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        expectedInP2P = amount.mul(supplyP2PExchangeRate);

        assertApproxEq(inP2P, expectedInP2P, 1e3, "in P2P");
        testEquality(onPool, 0, "on pool");
    }

    function testSupply5() public {
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

            expectedInP2P = inP2P.mul(supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerBorrower);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));

        expectedInP2P = (amount / 2).div(supplyP2PExchangeRate);
        uint256 expectedOnPool = (amount / 2).div(supplyPoolIndex);

        assertApproxEq(inP2P, expectedInP2P, 1e3, "in P2P");
        testEquality(onPool, expectedOnPool, "in pool");
    }

    function testSupplyMultipleTimes() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(cDai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = (2 * amount).div(supplyPoolIndex);

        (, uint256 onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    function testFailSupplyZero() public {
        positionsManager.supply(cDai, 0, 1, type(uint256).max);
    }
}
