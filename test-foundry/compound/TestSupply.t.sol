// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using CompoundMath for uint256;

    function testSupply1() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(supplyPoolIndex);

        assertEq(ERC20(cDai).balanceOf(address(morpho)), expectedOnPool, "balance of cToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        assertEq(onPool, expectedOnPool, "on pool");
        assertEq(inP2P, 0, "in peer-to-peer");
    }

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
        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        uint256 p2pSupplyIndex = lens.getUpdatedP2PSupplyIndex(cDai);
        uint256 expectedSupplyBalanceInP2P = amount.div(p2pSupplyIndex);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
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

        uint256 p2pSupplyIndex = lens.getUpdatedP2PSupplyIndex(cDai);
        uint256 expectedSupplyBalanceInP2P = amount.div(p2pSupplyIndex);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedSupplyBalanceOnPool = amount.div(supplyPoolIndex);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        assertEq(onPoolSupplier, expectedSupplyBalanceOnPool, "on pool supplier");
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "in peer-to-peer supplier");

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        assertEq(onPoolBorrower, 0, "on pool borrower");
        assertEq(inP2PBorrower, inP2PSupplier, "in peer-to-peer borrower");
    }

    function testSupply4() public {
        setMaxGasForMatchingHelper(
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

            assertEq(inP2P, expectedInP2P, "amount per borrower");
            assertEq(onPool, 0, "on pool per borrower");
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        expectedInP2P = amount.div(p2pSupplyIndex);

        assertEq(inP2P, expectedInP2P, "in peer-to-peer");
        assertEq(onPool, 0, "on pool");
    }

    function testSupply5() public {
        setMaxGasForMatchingHelper(
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
        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));

            expectedInP2P = amountPerBorrower.div(morpho.p2pBorrowIndex(cDai));

            assertEq(inP2P, expectedInP2P, "borrower in peer-to-peer");
            assertEq(onPool, 0, "borrower on pool");
        }

        (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        expectedInP2P = (amount / 2).div(p2pSupplyIndex);
        uint256 expectedOnPool = (amount / 2).div(supplyPoolIndex);

        assertEq(inP2P, expectedInP2P, "in peer-to-peer");
        assertEq(onPool, expectedOnPool, "in pool");
    }

    function testSupplyMultipleTimes() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(cDai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = (2 * amount).div(supplyPoolIndex);

        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPool, expectedOnPool);
    }

    function testFailSupplyZero() public {
        morpho.supply(cDai, 0, type(uint256).max);
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
        hevm.stopPrank();

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
}
