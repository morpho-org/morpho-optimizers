// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRatesLens is TestSetup {
    using WadRayMath for uint256;
    using SafeTransferLib for ERC20;

    function testGetRatesPerYear() public {
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

        assertEq(p2pSupplyRate, expectedP2PSupplyRate);
        assertEq(p2pBorrowRate, expectedP2PBorrowRate);
        assertEq(poolSupplyRate, expectedPoolSupplyRate);
        assertEq(poolBorrowRate, expectedPoolBorrowRate);
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

        assertApproxEqAbs(supplyRatePerYear, (p2pSupplyRate + poolSupplyRate) / 2, 1);
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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(p2pSupplyRate, poolSupplyRate, 1);
    }

    function testBorrowRateShouldEqualPoolRateWithFullBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

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

        assertEq(supplyRatePerYear, 0, "non zero supply rate per block");
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

        assertEq(borrowRatePerYear, 0, "non zero borrow rate per block");
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

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertEq(supplyRatePerYear, expectedSupplyRatePerYear, "unexpected supply rate per block");
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

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertEq(borrowRatePerYear, expectedBorrowRatePerYear, "unexpected borrow rate per block");
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

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerYear,
            expectedSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
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

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerYear,
            expectedBorrowRatePerYear,
            1,
            "unexpected borrow rate per block"
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

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
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

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1,
            "unexpected borrow rate per block"
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

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerYear,
            (p2pSupplyRatePerYear + poolSupplyRatePerYear) / 2,
            1,
            "unexpected supply rate per block"
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

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerYear,
            (p2pBorrowRatePerYear + poolBorrowRatePerYear) / 2,
            1,
            "unexpected borrow rate per block"
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

        morpho.setP2PDisabledStatus(aDai, true);

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
            1,
            "unexpected supply rate per block"
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

        morpho.setP2PDisabledStatus(aDai, true);

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
            1,
            "unexpected borrow rate per block"
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

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
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

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1,
            "unexpected borrow rate per block"
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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

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

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

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

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1,
            "unexpected borrow rate per block"
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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

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

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerYear,
            (p2pSupplyRatePerYear + poolSupplyRatePerYear) / 2,
            1,
            "unexpected supply rate per block"
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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

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

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerYear,
            (p2pBorrowRatePerYear + poolBorrowRatePerYear) / 2,
            1,
            "unexpected borrow rate per block"
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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

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

        assertApproxEqAbs(supplyRatePerYear, (p2pSupplyRate + poolSupplyRate) / 2, 1);
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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

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

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        supplier1.withdraw(aDai, type(uint256).max);

        (uint256 avgBorrowRate, , ) = lens.getAverageBorrowRatePerYear(aDai);
        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);

        assertApproxEqAbs(avgBorrowRate, reserve.currentVariableBorrowRate, 1);
    }

    function testInvertedSpread() public {
        // Full p2p on the DAI market.
        supplier1.approve(dai, 1 ether);
        supplier1.supply(aDai, 1 ether);
        borrower1.approve(aave, 1 ether);
        borrower1.supply(aAave, 1 ether);
        borrower1.borrow(aDai, 1 ether);

        // Invert spreads on DAI.
        (, uint256 poolBorrowRate) = _invertSpreadOnDai();

        (uint256 avgSupplyRate, , ) = lens.getAverageSupplyRatePerYear(aDai);
        (uint256 avgBorrowRate, , ) = lens.getAverageBorrowRatePerYear(aDai);
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerYear(aDai);

        assertEq(avgSupplyRate, poolBorrowRate);
        assertEq(avgBorrowRate, poolBorrowRate);
        assertEq(p2pSupplyRate, poolBorrowRate);
        assertEq(p2pBorrowRate, poolBorrowRate);
    }

    function testInvertedSpreadDelta() public {
        // Full p2p on the DAI market, with a 50% supply delta.
        uint256 supplyAmount = 1 ether;
        uint256 repayAmount = 0.5 ether;
        supplier1.approve(dai, supplyAmount);
        supplier1.supply(aDai, supplyAmount);
        borrower1.approve(aave, supplyAmount);
        borrower1.supply(aAave, supplyAmount);
        borrower1.borrow(aDai, supplyAmount);
        _setDefaultMaxGasForMatching(0, 0, 0, 0);
        borrower1.approve(dai, repayAmount);
        borrower1.repay(aDai, repayAmount);
        (uint256 p2pSupplyDelta, , , ) = morpho.deltas(aDai);
        assertEq(p2pSupplyDelta, repayAmount.rayDiv(pool.getReserveNormalizedIncome(dai)));

        // Invert spreads on DAI.
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = _invertSpreadOnDai();

        (uint256 avgSupplyRate, , ) = lens.getAverageSupplyRatePerYear(aDai);
        (uint256 avgBorrowRate, , ) = lens.getAverageBorrowRatePerYear(aDai);
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerYear(aDai);

        assertApproxEqAbs(avgSupplyRate, (poolBorrowRate + poolSupplyRate) / 2, 1e7);
        assertEq(avgBorrowRate, poolBorrowRate);
        assertApproxEqAbs(p2pSupplyRate, (poolBorrowRate + poolSupplyRate) / 2, 1e7);
        assertEq(p2pBorrowRate, poolBorrowRate);
    }

    function _invertSpreadOnDai() public returns (uint256 poolSupplyRate, uint256 poolBorrowRate) {
        uint256 VARIABLE_RATE = 2;
        uint256 FIXED_RATE = 1;

        // Borrow variable.
        uint256 amount = 100_000_000 ether;
        deal(usdc, address(1), to6Decimals(2 * amount));
        vm.startPrank(address(1));
        ERC20(usdc).safeApprove(address(pool), type(uint256).max);
        pool.deposit(usdc, to6Decimals(2 * amount), address(1), 0);
        pool.borrow(dai, amount, VARIABLE_RATE, 0, address(1));
        vm.stopPrank();

        // Borrow stable.
        // We do it with multiple borrowers, because the stable borrow is capped
        // (by users) in Aave, by a given percentage of the available liquidity.
        uint256 amountStable = 10_000_000 ether;
        for (uint160 i = 2; i <= 10; i++) {
            deal(usdc, address(i), to6Decimals(2 * amountStable));

            vm.startPrank(address(i));

            ERC20(usdc).safeApprove(address(pool), type(uint256).max);
            pool.deposit(usdc, to6Decimals(2 * amountStable), address(i), 0);
            pool.borrow(dai, amountStable, FIXED_RATE, 0, address(i));

            vm.stopPrank();
        }

        // Repay variable.
        vm.startPrank(address(1));
        ERC20(dai).safeApprove(address(pool), type(uint256).max);
        pool.repay(dai, amount, VARIABLE_RATE, address(1));
        vm.stopPrank();

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);

        // Return values.
        poolSupplyRate = reserve.currentLiquidityRate;
        poolBorrowRate = reserve.currentVariableBorrowRate;

        // Rates must be inverted.
        assertGt(poolSupplyRate, poolBorrowRate);
    }

    function _invertSpreadOnDaiWithStorageManipulation()
        internal
        returns (uint256 poolSupplyRate, uint256 poolBorrowRate)
    {
        // Keep the current supply rate.
        uint256 newPoolSupplyRate = pool.getReserveData(dai).currentLiquidityRate;
        // Make the borrow rate less than the supply rate.
        uint256 newPoolBorrowRate = newPoolSupplyRate / 2;
        // Rates are packed in the _reserves struct.
        uint256 newRates = (newPoolBorrowRate << 128) | newPoolSupplyRate;
        // Slot of the mapping _reserves is 53 to take into account 52 storage slots of VersionedInitializable plus the ILendingPoolAddressesProvider slot.
        // Offset in the ReserveData struct is 2.
        bytes32 rateSlot = bytes32(uint256(keccak256(abi.encode(address(dai), 53))) + uint256(2));
        vm.store(address(pool), rateSlot, bytes32(newRates));

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        poolSupplyRate = reserve.currentLiquidityRate;
        poolBorrowRate = reserve.currentVariableBorrowRate;
        // Rates must be inverted.
        assertGt(poolSupplyRate, poolBorrowRate);
    }
}
