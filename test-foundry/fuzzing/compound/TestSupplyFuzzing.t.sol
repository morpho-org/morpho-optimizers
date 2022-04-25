// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";


contract TestSupplyFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    
    function testSupply1(uint64 _amount, uint8 _asset) public {
        (address asset, address underlying) = getAsset(_asset);

        uint256 amount = _amount;
        hevm.assume(_amount > 0 && _amount <= ERC20(underlying).balanceOf(address(supplier1)));

        supplier1.approve(underlying, amount);
        supplier1.supply(asset, amount);

        uint256 supplyPoolIndex = ICToken(asset).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(supplyPoolIndex);

        assertEq(
            IERC20(asset).balanceOf(address(positionsManager)),
            expectedOnPool,
            "balance of cToken"
        );

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            asset,
            address(supplier1)
        );

        assertEq(onPool, expectedOnPool, "on pool");
        assertEq(inP2P, 0, "in P2P");
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
        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        (uint256 supplyP2PExchangeRate, ) = marketsManager.getUpdatedP2PExchangeRates(cDai);
        uint256 expectedSupplyBalanceInP2P = amount.div(supplyP2PExchangeRate);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        assertEq(onPoolSupplier, 0);
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P);

        assertEq(onPoolBorrower, 0);
        assertEq(inP2PBorrower, inP2PSupplier);
    }

    function testSupply3() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, 2 * amount);

        (uint256 supplyP2PExchangeRate, ) = marketsManager.getUpdatedP2PExchangeRates(cDai);
        uint256 expectedSupplyBalanceInP2P = amount.div(supplyP2PExchangeRate);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedSupplyBalanceOnPool = amount.div(supplyPoolIndex);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        assertEq(onPoolSupplier, expectedSupplyBalanceOnPool, "on pool supplier");
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "in P2P supplier");

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        assertEq(onPoolBorrower, 0, "on pool borrower");
        assertEq(inP2PBorrower, inP2PSupplier, "in P2P borrower");
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

            expectedInP2P = amountPerBorrower.div(marketsManager.borrowP2PExchangeRate(cDai));

            assertEq(inP2P, expectedInP2P, "amount per borrower");
            assertEq(onPool, 0, "on pool per borrower");
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        expectedInP2P = amount.div(supplyP2PExchangeRate);

        assertEq(inP2P, expectedInP2P, "in P2P");
        assertEq(onPool, 0, "on pool");
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

            expectedInP2P = amountPerBorrower.div(marketsManager.borrowP2PExchangeRate(cDai));

            assertEq(inP2P, expectedInP2P, "borrower in P2P");
            assertEq(onPool, 0, "borrower on pool");
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));

        expectedInP2P = (amount / 2).div(supplyP2PExchangeRate);
        uint256 expectedOnPool = (amount / 2).div(supplyPoolIndex);

        assertEq(inP2P, expectedInP2P, "in P2P");
        assertEq(onPool, expectedOnPool, "in pool");
    }

    function testSupplyMultipleTimes() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(cDai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = (2 * amount).div(supplyPoolIndex);

        (, uint256 onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPool, expectedOnPool);
    }

    function testFailSupplyZero() public {
        positionsManager.supply(cDai, 0, type(uint256).max);
    }

    function testSupplyRepayOnBehalf() public {
        uint256 amount = 1 ether;
        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        // Someone repays on behalf of the positionsManager.
        supplier2.approve(dai, cDai, amount);
        hevm.prank(address(supplier2));
        ICToken(cDai).repayBorrowBehalf(address(positionsManager), amount);
        hevm.stopPrank();

        // Supplier supplies in P2P. Not supposed to revert.
        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);
    }
}
