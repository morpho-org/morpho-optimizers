// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRatesLens is TestSetup {
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;

    function testGetRatesPerYear() public {
        supplier1.aaveSupply(dai, 1 ether); // Update pool rates.

        hevm.roll(block.number + 1_000);
        (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        ) = lens.getRatesPerYear(aDai);

        (uint256 expectedP2PSupplyRate, uint256 expectedP2PBorrowRate) = getApproxP2PRates(aDai);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        uint256 expectedPoolSupplyRate = reserve.currentLiquidityRate;
        uint256 expectedPoolBorrowRate = reserve.currentVariableBorrowRate;

        assertApproxEqAbs(p2pSupplyRate, expectedP2PSupplyRate, 1);
        assertApproxEqAbs(p2pBorrowRate, expectedP2PBorrowRate, 1);
        assertApproxEqAbs(poolSupplyRate, expectedPoolSupplyRate, 1);
        assertApproxEqAbs(poolBorrowRate, expectedPoolBorrowRate, 1);
    }

    function testSupplyRateShouldEqual0WhenNoSupply() public {
        uint256 supplyRatePerYear = lens.getCurrentUserSupplyRatePerYear(aDai, address(supplier1));

        assertEq(supplyRatePerYear, 0);
    }

    function testBorrowRateShouldEqual0WhenNoBorrow() public {
        uint256 borrowRatePerYear = lens.getCurrentUserBorrowRatePerYear(aDai, address(borrower1));

        assertEq(borrowRatePerYear, 0);
    }

    function testUserSupplyRateShouldEqualPoolRateWhenNotMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 supplyRatePerYear = lens.getCurrentUserSupplyRatePerYear(aDai, address(supplier1));

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        assertApproxEqAbs(supplyRatePerYear, reserve.currentLiquidityRate, 1);
    }

    function testUserBorrowRateShouldEqualPoolRateWhenNotMatched() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        uint256 borrowRatePerYear = lens.getCurrentUserBorrowRatePerYear(aDai, address(borrower1));

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        assertApproxEqAbs(borrowRatePerYear, reserve.currentVariableBorrowRate, 1);
    }

    function testUserSupplyBorrowRatesShouldEqualP2PRatesWhenFullyMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wbtc, to8Decimals(amount));
        supplier1.supply(aWbtc, to8Decimals(amount));

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        uint256 supplyRatePerYear = lens.getCurrentUserSupplyRatePerYear(aDai, address(supplier1));
        uint256 borrowRatePerYear = lens.getCurrentUserBorrowRatePerYear(aDai, address(borrower1));
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(supplyRatePerYear, p2pSupplyRate, 1, "unexpected supply rate");
        assertApproxEqAbs(borrowRatePerYear, p2pBorrowRate, 1, "unexpected borrow rate");
    }

    function testUserSupplyRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wbtc, to8Decimals(amount));
        supplier1.supply(aWbtc, to8Decimals(amount));

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount / 2);

        uint256 supplyRatePerYear = lens.getCurrentUserSupplyRatePerYear(aDai, address(supplier1));
        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(supplyRatePerYear, (p2pSupplyRate + poolSupplyRate) / 2, 1e3);
    }

    function testUserBorrowRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wbtc, to8Decimals(amount));
        supplier1.supply(aWbtc, to8Decimals(amount));
        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);
        borrower1.borrow(aDai, amount);

        uint256 borrowRatePerYear = lens.getCurrentUserBorrowRatePerYear(aDai, address(borrower1));
        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(borrowRatePerYear, (p2pBorrowRate + poolBorrowRate) / 2, 1);
    }

    function testSupplyRateShouldEqualPoolRateWithFullSupplyDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(p2pSupplyRate, poolSupplyRate, 100);
    }

    function testBorrowRateShouldEqualPoolRateWithFullBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        supplier1.withdraw(aDai, type(uint256).max);

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(p2pBorrowRate, poolBorrowRate, 1e3);
    }

    function testNextSupplyRateShouldEqual0WhenNoSupply() public {
        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), 0);

        assertEq(supplyRatePerYear, 0, "non zero supply rate per year");
        assertEq(balanceOnPool, 0, "non zero pool balance");
        assertEq(balanceInP2P, 0, "non zero p2p balance");
        assertEq(totalBalance, 0, "non zero total balance");
    }

    function testNextBorrowRateShouldEqual0WhenNoBorrow() public {
        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), 0);

        assertEq(borrowRatePerYear, 0, "non zero borrow rate per year");
        assertEq(balanceOnPool, 0, "non zero pool balance");
        assertEq(balanceInP2P, 0, "non zero p2p balance");
        assertEq(totalBalance, 0, "non zero total balance");
    }

    function testNextSupplyRateShouldEqualCurrentRateWhenNoNewSupply() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), 0);

        uint256 expectedSupplyRatePerYear = lens.getCurrentUserSupplyRatePerYear(
            aDai,
            address(supplier1)
        );
        (
            uint256 expectedBalanceInP2P,
            uint256 expectedBalanceOnPool,
            uint256 expectedTotalBalance
        ) = lens.getCurrentSupplyBalanceInOf(aDai, address(supplier1));

        assertGt(supplyRatePerYear, 0, "zero supply rate per year");
        assertEq(supplyRatePerYear, expectedSupplyRatePerYear, "unexpected supply rate per year");
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedTotalBalance, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualCurrentRateWhenNoNewBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), 0);

        uint256 expectedBorrowRatePerYear = lens.getCurrentUserBorrowRatePerYear(
            aDai,
            address(borrower1)
        );
        (
            uint256 expectedBalanceInP2P,
            uint256 expectedBalanceOnPool,
            uint256 expectedTotalBalance
        ) = lens.getCurrentBorrowBalanceInOf(aDai, address(borrower1));

        assertGt(borrowRatePerYear, 0, "zero borrow rate per year");
        assertEq(borrowRatePerYear, expectedBorrowRatePerYear, "unexpected borrow rate per year");
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedTotalBalance, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualPoolRateWhenNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), amount);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        uint256 expectedSupplyRatePerYear = reserve.currentLiquidityRate;
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);

        assertGt(supplyRatePerYear, 0, "zero supply rate per year");
        assertApproxEqAbs(
            supplyRatePerYear,
            expectedSupplyRatePerYear,
            1e22,
            "unexpected supply rate per year"
        );
        assertEq(
            balanceOnPool,
            amount.rayDiv(poolSupplyIndex).rayMul(poolSupplyIndex),
            "unexpected pool balance"
        );
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertEq(
            totalBalance,
            amount.rayDiv(poolSupplyIndex).rayMul(poolSupplyIndex),
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualPoolRateWhenNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(supplier1), amount);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        uint256 expectedBorrowRatePerYear = reserve.currentVariableBorrowRate;

        assertGt(borrowRatePerYear, 0, "zero borrow rate per year");
        assertApproxEqAbs(
            borrowRatePerYear,
            expectedBorrowRatePerYear,
            1e22,
            "unexpected borrow rate per year"
        );
        assertApproxEqAbs(balanceOnPool, amount, 1, "unexpected pool balance");
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, amount, 1, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWhenFullMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , , ) = lens.getRatesPerYear(aDai);

        morpho.updateIndexes(aDai);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        uint256 expectedBalanceInP2P = amount.rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per year");
        assertApproxEqAbs(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1e22,
            "unexpected supply rate per year"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWhenFullMatch() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , ) = lens.getRatesPerYear(aDai);

        morpho.updateIndexes(aDai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        uint256 expectedBalanceInP2P = amount.rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per year");
        assertApproxEqAbs(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1e22,
            "unexpected borrow rate per year"
        );
        assertApproxEqAbs(balanceOnPool, 0, 1, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualMidrateWhenHalfMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount / 2);

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , uint256 poolSupplyRatePerYear, ) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        uint256 expectedBalanceOnPool = (amount / 2).rayDiv(poolSupplyIndex).rayMul(
            poolSupplyIndex
        );
        uint256 expectedBalanceInP2P = (amount / 2).rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per year");
        assertApproxEqAbs(
            supplyRatePerYear,
            (p2pSupplyRatePerYear + poolSupplyRatePerYear) / 2,
            1e22,
            "unexpected supply rate per year"
        );
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualMidrateWhenHalfMatch() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount / 2);

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , uint256 poolBorrowRatePerYear) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(dai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        uint256 expectedBalanceOnPool = (amount / 2).rayDiv(poolBorrowIndex).rayMul(
            poolBorrowIndex
        );
        uint256 expectedBalanceInP2P = (amount / 2).rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per year");
        assertApproxEqAbs(
            borrowRatePerYear,
            (p2pBorrowRatePerYear + poolBorrowRatePerYear) / 2,
            1e22,
            "unexpected borrow rate per year"
        );
        assertApproxEqAbs(balanceOnPool, expectedBalanceOnPool, 1, "unexpected pool balance");
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1, "unexpected p2p balance");
        assertApproxEqAbs(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            1,
            "unexpected total balance"
        );
    }

    function testNextSupplyRateShouldEqualPoolRateWhenFullMatchButP2PDisabled() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1000);

        morpho.setIsP2PDisabled(aDai, true);

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), amount);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        uint256 expectedPoolSupplyRate = reserve.currentLiquidityRate;
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);

        assertApproxEqAbs(
            supplyRatePerYear,
            expectedPoolSupplyRate,
            1e22,
            "unexpected supply rate per year"
        );
        assertEq(
            balanceOnPool,
            amount.rayDiv(poolSupplyIndex).rayMul(poolSupplyIndex),
            "unexpected pool balance"
        );
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertEq(
            totalBalance,
            amount.rayDiv(poolSupplyIndex).rayMul(poolSupplyIndex),
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualPoolRateWhenFullMatchButP2PDisabled() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        hevm.roll(block.number + 1000);

        morpho.setIsP2PDisabled(aDai, true);

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), amount);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        uint256 expectedBorrowRatePerYear = reserve.currentVariableBorrowRate;

        assertApproxEqAbs(
            borrowRatePerYear,
            expectedBorrowRatePerYear,
            1e22,
            "unexpected borrow rate per year"
        );
        assertApproxEqAbs(balanceOnPool, amount, 1, "unexpected pool balance");
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, amount, 1, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWhenDoubleSupply() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount / 2);

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), amount / 2);

        (uint256 p2pSupplyRatePerYear, , , ) = lens.getRatesPerYear(aDai);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per year");
        assertApproxEqAbs(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1e22,
            "unexpected supply rate per year"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, expectedBalanceInP2P, 1, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWhenDoubleBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), amount / 2);

        (, uint256 p2pBorrowRatePerYear, , ) = lens.getRatesPerYear(aDai);

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per year");
        assertApproxEqAbs(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1e21,
            "unexpected borrow rate per year"
        );
        assertApproxEqAbs(balanceOnPool, 0, 1, "unexpected pool balance");
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, expectedBalanceInP2P, 1, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWithFullBorrowDeltaAndNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        supplier1.withdraw(aDai, type(uint256).max);

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , , ) = lens.getRatesPerYear(aDai);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per year");
        assertApproxEqAbs(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1e22,
            "unexpected supply rate per year"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWithFullSupplyDeltaAndNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , ) = lens.getRatesPerYear(aDai);

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per year");
        assertApproxEqAbs(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1e22,
            "unexpected borrow rate per year"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualMidrateWithHalfBorrowDeltaAndNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount / 2);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 1);

        supplier1.withdraw(aDai, type(uint256).max);

        (
            uint256 supplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , uint256 poolSupplyRatePerYear, ) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        uint256 expectedBalanceOnPool = (amount / 2).rayDiv(poolSupplyIndex).rayMul(
            poolSupplyIndex
        );
        uint256 expectedBalanceInP2P = (amount / 2).rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per year");
        assertApproxEqAbs(
            supplyRatePerYear,
            (p2pSupplyRatePerYear + poolSupplyRatePerYear) / 2,
            1e22,
            "unexpected supply rate per year"
        );
        assertApproxEqAbs(balanceOnPool, expectedBalanceOnPool, 1, "unexpected pool balance");
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1, "unexpected p2p balance");
        assertEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualMidrateWithHalfSupplyDeltaAndNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount / 2);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 1);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (
            uint256 borrowRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , uint256 poolBorrowRatePerYear) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(dai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        uint256 expectedBalanceOnPool = (amount / 2).rayDiv(poolBorrowIndex).rayMul(
            poolBorrowIndex
        );
        uint256 expectedBalanceInP2P = (amount / 2).rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per year");
        assertApproxEqAbs(
            borrowRatePerYear,
            (p2pBorrowRatePerYear + poolBorrowRatePerYear) / 2,
            1e22,
            "unexpected borrow rate per year"
        );
        assertApproxEqAbs(balanceOnPool, expectedBalanceOnPool, 1, "unexpected pool balance");
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1, "unexpected p2p balance");
        assertEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            "unexpected total balance"
        );
    }

    function testRatesShouldBeConstantWhenSupplyDeltaWithoutInteraction() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount / 2);

        borrower2.approve(aave, amount);
        borrower2.supply(aAave, amount);
        borrower2.borrow(aDai, amount / 2);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 1);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (
            uint256 p2pSupplyRateBefore,
            uint256 p2pBorrowRateBefore,
            uint256 poolSupplyRateBefore,
            uint256 poolBorrowRateBefore
        ) = lens.getRatesPerYear(aDai);

        hevm.roll(block.number + 1_000_000);

        (
            uint256 p2pSupplyRateAfter,
            uint256 p2pBorrowRateAfter,
            uint256 poolSupplyRateAfter,
            uint256 poolBorrowRateAfter
        ) = lens.getRatesPerYear(aDai);

        assertEq(p2pSupplyRateBefore, p2pSupplyRateAfter);
        assertEq(p2pBorrowRateBefore, p2pBorrowRateAfter);
        assertEq(poolSupplyRateBefore, poolSupplyRateAfter);
        assertEq(poolBorrowRateBefore, poolBorrowRateAfter);
    }

    function testAverageSupplyRateShouldEqual0WhenNoSupply() public {
        (uint256 supplyRatePerYear, uint256 p2pSupplyAmount, uint256 poolSupplyAmount) = lens
        .getAverageSupplyRatePerYear(aDai);

        assertEq(supplyRatePerYear, 0);
        assertEq(p2pSupplyAmount, 0);
        assertEq(poolSupplyAmount, 0);
    }

    function testAverageBorrowRateShouldEqual0WhenNoBorrow() public {
        (uint256 borrowRatePerYear, uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = lens
        .getAverageBorrowRatePerYear(aDai);

        assertEq(borrowRatePerYear, 0);
        assertEq(p2pBorrowAmount, 0);
        assertEq(poolBorrowAmount, 0);
    }

    function testPoolSupplyAmountShouldBeEqualToPoolAmount() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        hevm.roll(block.number + 1_000_000);

        (, , uint256 poolSupplyAmount) = lens.getAverageSupplyRatePerYear(aDai);

        assertEq(poolSupplyAmount, IAToken(aDai).balanceOf(address(morpho)));
    }

    function testPoolBorrowAmountShouldBeEqualToPoolAmount() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1_000_000);

        (, , uint256 poolBorrowAmount) = lens.getAverageBorrowRatePerYear(aDai);

        assertApproxEqAbs(poolBorrowAmount, amount, 1);
    }

    function testAverageSupplyRateShouldEqualPoolRateWhenNoMatch() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        (uint256 supplyRatePerYear, uint256 p2pSupplyAmount, uint256 poolSupplyAmount) = lens
        .getAverageSupplyRatePerYear(aDai);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);

        assertApproxEqAbs(supplyRatePerYear, reserve.currentLiquidityRate, 1);
        assertApproxEqAbs(poolSupplyAmount, amount, 1);
        assertEq(p2pSupplyAmount, 0);
    }

    function testAverageBorrowRateShouldEqualPoolRateWhenNoMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        (uint256 borrowRatePerYear, uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = lens
        .getAverageBorrowRatePerYear(aDai);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);

        assertApproxEqAbs(borrowRatePerYear, reserve.currentVariableBorrowRate, 1);
        assertEq(poolBorrowAmount, amount);
        assertEq(p2pBorrowAmount, 0);
    }

    function testAverageRatesShouldEqualP2PRatesWhenFullyMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(aave, amount);
        supplier1.supply(aAave, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        (uint256 supplyRatePerYear, uint256 p2pSupplyAmount, uint256 poolSupplyAmount) = lens
        .getAverageSupplyRatePerYear(aDai);
        (uint256 borrowRatePerYear, uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = lens
        .getAverageBorrowRatePerYear(aDai);
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(supplyRatePerYear, p2pSupplyRate, 1, "unexpected supply rate");
        assertApproxEqAbs(borrowRatePerYear, p2pBorrowRate, 1, "unexpected borrow rate");
        assertApproxEqAbs(poolSupplyAmount, poolBorrowAmount, 1);
        assertApproxEqAbs(poolBorrowAmount, 0, 1);
        assertEq(p2pSupplyAmount, p2pBorrowAmount);
        assertApproxEqAbs(p2pBorrowAmount, amount, 1);
    }

    function testAverageSupplyRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount / 2);

        (uint256 supplyRatePerYear, , ) = lens.getAverageSupplyRatePerYear(aDai);
        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(supplyRatePerYear, (p2pSupplyRate + poolSupplyRate) / 2, 1e3);
    }

    function testAverageBorrowRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        (uint256 borrowRatePerYear, , ) = lens.getAverageBorrowRatePerYear(aDai);
        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(borrowRatePerYear, (p2pBorrowRate + poolBorrowRate) / 2, 1);
    }

    function testAverageSupplyRateShouldEqualPoolRateWithFullSupplyDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aUsdc, to6Decimals(amount));

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        borrower1.approve(usdc, type(uint256).max);
        borrower1.repay(aUsdc, type(uint256).max);

        (uint256 avgSupplyRate, , ) = lens.getAverageSupplyRatePerYear(aUsdc);
        DataTypes.ReserveData memory reserve = pool.getReserveData(usdc);

        assertApproxEqAbs(avgSupplyRate, reserve.currentLiquidityRate, 2);
    }

    function testAverageBorrowRateShouldEqualPoolRateWithFullBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        supplier1.withdraw(aDai, type(uint256).max);

        (uint256 avgBorrowRate, , ) = lens.getAverageBorrowRatePerYear(aDai);
        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);

        assertApproxEqAbs(avgBorrowRate, reserve.currentVariableBorrowRate, 1);
    }

    function testRatesWithInvertedSpread() public {
        // Full p2p on the DAI market.
        supplier1.approve(dai, 1 ether);
        supplier1.supply(aDai, 1 ether);
        borrower1.approve(aave, 1 ether);
        borrower1.supply(aAave, 1 ether);
        borrower1.borrow(aDai, 1 ether);

        // Invert spreads on DAI.
        (, uint256 poolBorrowRate) = _invertPoolSpread(dai);

        (uint256 avgSupplyRate, , ) = lens.getAverageSupplyRatePerYear(aDai);
        (uint256 avgBorrowRate, , ) = lens.getAverageBorrowRatePerYear(aDai);
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerYear(aDai);

        assertEq(avgSupplyRate, poolBorrowRate);
        assertEq(avgBorrowRate, poolBorrowRate);
        assertEq(p2pSupplyRate, poolBorrowRate);
        assertEq(p2pBorrowRate, poolBorrowRate);
    }

    function testRatesWithInvertedSpreadAndHalfSupplyDelta() public {
        // Full p2p on the DAI market, with a 50% supply delta.
        uint256 supplyAmount = 1 ether;
        uint256 repayAmount = supplyAmount / 2;

        supplier1.approve(dai, supplyAmount);
        supplier1.supply(aDai, supplyAmount);

        borrower1.approve(aave, supplyAmount);
        borrower1.supply(aAave, supplyAmount);
        borrower1.borrow(aDai, supplyAmount);

        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        borrower1.approve(dai, repayAmount);
        borrower1.repay(aDai, repayAmount);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        reserve.currentLiquidityRate = 0.03e27;
        reserve.currentVariableBorrowRate = 0.02e27;
        reserve.currentStableBorrowRate = 0.04e27;
        vm.mockCall(
            reserve.interestRateStrategyAddress,
            abi.encodeWithSelector(IReserveInterestRateStrategy.calculateInterestRates.selector),
            abi.encode(
                reserve.currentLiquidityRate,
                reserve.currentStableBorrowRate,
                reserve.currentVariableBorrowRate
            )
        );
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(ILendingPool.getReserveData.selector),
            abi.encode(reserve)
        );

        (uint256 avgSupplyRate, , ) = lens.getAverageSupplyRatePerYear(aDai);
        (uint256 avgBorrowRate, , ) = lens.getAverageBorrowRatePerYear(aDai);
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerYear(aDai);

        assertEq(
            avgSupplyRate,
            (reserve.currentVariableBorrowRate + reserve.currentLiquidityRate) / 2,
            "avg supply rate"
        );
        assertEq(avgBorrowRate, reserve.currentVariableBorrowRate, "avg borrow rate");
        assertEq(
            p2pSupplyRate,
            (reserve.currentVariableBorrowRate + reserve.currentLiquidityRate) / 2,
            "p2p supply rate"
        );
        assertEq(p2pBorrowRate, reserve.currentVariableBorrowRate, "p2p borrow rate");
    }
}
