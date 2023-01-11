// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRatesLens is TestSetup {
    using CompoundMath for uint256;

    function testGetRatesPerBlock() public {
        supplier1.compoundSupply(cDai, 1 ether); // Update pool rates.

        hevm.roll(block.number + 1_000);
        (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        ) = lens.getRatesPerBlock(cDai);

        (uint256 expectedP2PSupplyRate, uint256 expectedP2PBorrowRate) = getApproxP2PRates(cDai);
        uint256 expectedPoolSupplyRate = ICToken(cDai).supplyRatePerBlock();
        uint256 expectedPoolBorrowRate = ICToken(cDai).borrowRatePerBlock();

        assertApproxEqAbs(p2pSupplyRate, expectedP2PSupplyRate, 1);
        assertApproxEqAbs(p2pBorrowRate, expectedP2PBorrowRate, 1);
        assertApproxEqAbs(poolSupplyRate, expectedPoolSupplyRate, 1);
        assertApproxEqAbs(poolBorrowRate, expectedPoolBorrowRate, 1);
    }

    function testSupplyRateShouldEqual0WhenNoSupply() public {
        uint256 supplyRatePerBlock = lens.getCurrentUserSupplyRatePerBlock(
            cDai,
            address(supplier1)
        );

        assertEq(supplyRatePerBlock, 0);
    }

    function testBorrowRateShouldEqual0WhenNoBorrow() public {
        uint256 borrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            cDai,
            address(borrower1)
        );

        assertEq(borrowRatePerBlock, 0);
    }

    function testUserSupplyRateShouldEqualPoolRateWhenNotMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 supplyRatePerBlock = lens.getCurrentUserSupplyRatePerBlock(
            cDai,
            address(supplier1)
        );

        assertApproxEqAbs(supplyRatePerBlock, ICToken(cDai).supplyRatePerBlock(), 1);
    }

    function testUserBorrowRateShouldEqualPoolRateWhenNotMatched() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        uint256 borrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            cDai,
            address(borrower1)
        );

        assertApproxEqAbs(borrowRatePerBlock, ICToken(cDai).borrowRatePerBlock(), 1);
    }

    function testUserRatesShouldEqualP2PRatesWhenFullyMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        uint256 supplyRatePerBlock = lens.getCurrentUserSupplyRatePerBlock(
            cDai,
            address(supplier1)
        );
        uint256 borrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            cDai,
            address(borrower1)
        );
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(supplyRatePerBlock, p2pSupplyRate, 1, "unexpected supply rate");
        assertApproxEqAbs(borrowRatePerBlock, p2pBorrowRate, 1, "unexpected borrow rate");
    }

    function testUserSupplyRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        uint256 supplyRatePerBlock = lens.getCurrentUserSupplyRatePerBlock(
            cDai,
            address(supplier1)
        );
        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(supplyRatePerBlock, (p2pSupplyRate + poolSupplyRate) / 2, 1);
    }

    function testUserBorrowRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);
        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(cDai, amount / 2);
        borrower1.borrow(cDai, amount);

        uint256 borrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            cDai,
            address(borrower1)
        );
        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(borrowRatePerBlock, (p2pBorrowRate + poolBorrowRate) / 2, 1);
    }

    function testSupplyRateShouldEqualPoolRateWithFullSupplyDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(p2pSupplyRate, poolSupplyRate, 1);
    }

    function testBorrowRateShouldEqualPoolRateWithFullBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        supplier1.withdraw(cDai, type(uint256).max);

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(p2pBorrowRate, poolBorrowRate, 1);
    }

    function testNextSupplyRateShouldEqual0WhenNoSupply() public {
        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), 0);

        assertEq(supplyRatePerBlock, 0, "non zero supply rate per block");
        assertEq(balanceOnPool, 0, "non zero pool balance");
        assertEq(balanceInP2P, 0, "non zero p2p balance");
        assertEq(totalBalance, 0, "non zero total balance");
    }

    function testNextBorrowRateShouldEqual0WhenNoBorrow() public {
        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), 0);

        assertEq(borrowRatePerBlock, 0, "non zero borrow rate per block");
        assertEq(balanceOnPool, 0, "non zero pool balance");
        assertEq(balanceInP2P, 0, "non zero p2p balance");
        assertEq(totalBalance, 0, "non zero total balance");
    }

    function testNextSupplyRateShouldEqualCurrentRateWhenNoNewSupply() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), 0);

        uint256 expectedSupplyRatePerBlock = lens.getCurrentUserSupplyRatePerBlock(
            cDai,
            address(supplier1)
        );
        (
            uint256 expectedBalanceOnPool,
            uint256 expectedBalanceInP2P,
            uint256 expectedTotalBalance
        ) = lens.getCurrentSupplyBalanceInOf(cDai, address(supplier1));

        assertGt(supplyRatePerBlock, 0, "zero supply rate per block");
        assertEq(
            supplyRatePerBlock,
            expectedSupplyRatePerBlock,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedTotalBalance, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualCurrentRateWhenNoNewBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), 0);

        uint256 expectedBorrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            cDai,
            address(borrower1)
        );
        (
            uint256 expectedBalanceOnPool,
            uint256 expectedBalanceInP2P,
            uint256 expectedTotalBalance
        ) = lens.getCurrentBorrowBalanceInOf(cDai, address(borrower1));

        assertGt(borrowRatePerBlock, 0, "zero borrow rate per block");
        assertEq(
            borrowRatePerBlock,
            expectedBorrowRatePerBlock,
            "unexpected borrow rate per block"
        );
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedTotalBalance, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualPoolRateWhenNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), amount);

        uint256 expectedSupplyRatePerBlock = ICToken(cDai).supplyRatePerBlock();
        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();

        assertGt(supplyRatePerBlock, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerBlock,
            expectedSupplyRatePerBlock,
            1e6,
            "unexpected supply rate per block"
        );
        assertEq(
            balanceOnPool,
            amount.div(poolSupplyIndex).mul(poolSupplyIndex),
            "unexpected pool balance"
        );
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertEq(
            totalBalance,
            amount.div(poolSupplyIndex).mul(poolSupplyIndex),
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualPoolRateWhenNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(supplier1), amount);

        uint256 expectedBorrowRatePerBlock = ICToken(cDai).borrowRatePerBlock();

        assertGt(borrowRatePerBlock, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerBlock,
            expectedBorrowRatePerBlock,
            1e6,
            "unexpected borrow rate per block"
        );
        assertApproxEqAbs(balanceOnPool, amount, 1, "unexpected pool balance");
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, amount, 1, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWhenFullMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerBlock, , , ) = lens.getRatesPerBlock(cDai);

        morpho.updateP2PIndexes(cDai);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);

        uint256 expectedBalanceInP2P = amount.div(p2pSupplyIndex).mul(p2pSupplyIndex);

        assertGt(supplyRatePerBlock, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerBlock,
            p2pSupplyRatePerBlock,
            1e6,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWhenFullMatch() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerBlock, , ) = lens.getRatesPerBlock(cDai);

        morpho.updateP2PIndexes(cDai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);

        uint256 expectedBalanceInP2P = amount.div(p2pBorrowIndex).mul(p2pBorrowIndex);

        assertGt(borrowRatePerBlock, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerBlock,
            p2pBorrowRatePerBlock,
            1e6,
            "unexpected borrow rate per block"
        );
        assertApproxEqAbs(balanceOnPool, 0, 1e6, "unexpected pool balance"); // compound rounding error at supply
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualMidrateWhenHalfMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerBlock, , uint256 poolSupplyRatePerBlock, ) = lens.getRatesPerBlock(
            cDai
        );

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);

        uint256 expectedBalanceOnPool = (amount / 2).div(poolSupplyIndex).mul(poolSupplyIndex);
        uint256 expectedBalanceInP2P = (amount / 2).div(p2pSupplyIndex).mul(p2pSupplyIndex);

        assertGt(supplyRatePerBlock, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerBlock,
            (p2pSupplyRatePerBlock + poolSupplyRatePerBlock) / 2,
            1e6,
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
        supplier1.supply(cDai, amount / 2);

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerBlock, , uint256 poolBorrowRatePerBlock) = lens.getRatesPerBlock(
            cDai
        );

        uint256 poolBorrowIndex = ICToken(cDai).borrowIndex();
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);

        uint256 expectedBalanceOnPool = (amount / 2).div(poolBorrowIndex).mul(poolBorrowIndex);
        uint256 expectedBalanceInP2P = (amount / 2).div(p2pBorrowIndex).mul(p2pBorrowIndex);

        assertGt(borrowRatePerBlock, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerBlock,
            (p2pBorrowRatePerBlock + poolBorrowRatePerBlock) / 2,
            1,
            "unexpected borrow rate per block"
        );
        assertApproxEqAbs(balanceOnPool, expectedBalanceOnPool, 1e9, "unexpected pool balance");
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1e9, "unexpected p2p balance");
        assertApproxEqAbs(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            1e9,
            "unexpected total balance"
        );
    }

    function testNextSupplyRateShouldEqualPoolRateWhenFullMatchButP2PDisabled() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 1000);

        morpho.setIsP2PDisabled(cDai, true);

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), amount);

        uint256 expectedSupplyRatePerBlock = ICToken(cDai).supplyRatePerBlock();
        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();

        assertApproxEqAbs(
            supplyRatePerBlock,
            expectedSupplyRatePerBlock,
            1e6,
            "unexpected supply rate per block"
        );
        assertEq(
            balanceOnPool,
            amount.div(poolSupplyIndex).mul(poolSupplyIndex),
            "unexpected pool balance"
        );
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertEq(
            totalBalance,
            amount.div(poolSupplyIndex).mul(poolSupplyIndex),
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualPoolRateWhenFullMatchButP2PDisabled() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        hevm.roll(block.number + 1000);

        morpho.setIsP2PDisabled(cDai, true);

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), amount);

        uint256 expectedBorrowRatePerBlock = ICToken(cDai).borrowRatePerBlock();

        assertApproxEqAbs(
            borrowRatePerBlock,
            expectedBorrowRatePerBlock,
            1e6,
            "unexpected borrow rate per block"
        );
        assertApproxEqAbs(balanceOnPool, amount, 1, "unexpected pool balance");
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, amount, 1, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWhenDoubleSupply() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount / 2);

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), amount / 2);

        (uint256 p2pSupplyRatePerBlock, , , ) = lens.getRatesPerBlock(cDai);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 expectedBalanceInP2P = amount.div(p2pSupplyIndex).mul(p2pSupplyIndex);

        assertGt(supplyRatePerBlock, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerBlock,
            p2pSupplyRatePerBlock,
            1e6,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1e9, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, expectedBalanceInP2P, 1e9, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWhenDoubleBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), amount / 2);

        (, uint256 p2pBorrowRatePerBlock, , ) = lens.getRatesPerBlock(cDai);

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
        uint256 expectedBalanceInP2P = amount.div(p2pBorrowIndex).mul(p2pBorrowIndex);

        assertGt(borrowRatePerBlock, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerBlock,
            p2pBorrowRatePerBlock,
            1e6,
            "unexpected borrow rate per block"
        );
        assertApproxEqAbs(balanceOnPool, 0, 1e9, "unexpected pool balance"); // compound rounding errors
        assertApproxEqAbs(balanceInP2P, expectedBalanceInP2P, 1e9, "unexpected p2p balance");
        assertApproxEqAbs(totalBalance, expectedBalanceInP2P, 1e9, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWithFullBorrowDeltaAndNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        supplier1.withdraw(cDai, type(uint256).max);

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerBlock, , , ) = lens.getRatesPerBlock(cDai);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 expectedBalanceInP2P = amount.div(p2pSupplyIndex).mul(p2pSupplyIndex);

        assertGt(supplyRatePerBlock, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerBlock,
            p2pSupplyRatePerBlock,
            1e6,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWithFullSupplyDeltaAndNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerBlock, , ) = lens.getRatesPerBlock(cDai);

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
        uint256 expectedBalanceInP2P = amount.div(p2pBorrowIndex).mul(p2pBorrowIndex);

        assertGt(borrowRatePerBlock, 0, "zero borrow rate per block");
        assertApproxEqAbs(
            borrowRatePerBlock,
            p2pBorrowRatePerBlock,
            1e6,
            "unexpected borrow rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualMidrateWithHalfBorrowDeltaAndNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(cDai, amount / 2);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 1);

        supplier1.withdraw(cDai, type(uint256).max);

        uint256 daiBorrowdelta; // should be (amount / 2) but compound rounding leads to a slightly different amount which we need to compute
        {
            (, uint256 p2pBorrowDelta, , ) = morpho.deltas(cDai);
            daiBorrowdelta = p2pBorrowDelta.mul(ICToken(cDai).borrowIndex());
        }

        (
            uint256 supplyRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserSupplyRatePerBlock(cDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerBlock, , uint256 poolSupplyRatePerBlock, ) = lens.getRatesPerBlock(
            cDai
        );

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);

        uint256 expectedBalanceOnPool = (amount - daiBorrowdelta).div(poolSupplyIndex).mul(
            poolSupplyIndex
        );
        uint256 expectedBalanceInP2P = daiBorrowdelta.div(p2pSupplyIndex).mul(p2pSupplyIndex);

        assertGt(supplyRatePerBlock, 0, "zero supply rate per block");
        assertApproxEqAbs(
            supplyRatePerBlock,
            (p2pSupplyRatePerBlock + poolSupplyRatePerBlock) / 2,
            100,
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

    function testNextBorrowRateShouldEqualMidrateWithHalfSupplyDeltaAndNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(cDai, amount / 2);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 1);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        uint256 daiSupplydelta; // should be (amount / 2) but compound rounding leads to a slightly different amount which we need to compute
        {
            (uint256 p2pSupplyDelta, , , ) = morpho.deltas(cDai);
            daiSupplydelta = p2pSupplyDelta.mul(ICToken(cDai).exchangeRateCurrent());
        }

        (
            uint256 borrowRatePerBlock,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextUserBorrowRatePerBlock(cDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerBlock, , uint256 poolBorrowRatePerBlock) = lens.getRatesPerBlock(
            cDai
        );

        uint256 poolBorrowIndex = ICToken(cDai).borrowIndex();
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);

        uint256 expectedBalanceOnPool = (amount - daiSupplydelta).div(poolBorrowIndex).mul(
            poolBorrowIndex
        );
        uint256 expectedBalanceInP2P = daiSupplydelta.div(p2pBorrowIndex).mul(p2pBorrowIndex);

        assertGt(borrowRatePerBlock, p2pBorrowRatePerBlock, "borrow rate higher than p2p rate");
        assertLt(borrowRatePerBlock, poolBorrowRatePerBlock, "borrow rate lower than pool rate");
        assertApproxEqAbs(
            borrowRatePerBlock,
            (p2pBorrowRatePerBlock + poolBorrowRatePerBlock) / 2,
            100,
            "unexpected borrow rate per block"
        );
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            "unexpected total balance"
        );
    }

    function testRatesShouldBeConstantWhenSupplyDeltaWithoutInteraction() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        borrower2.approve(wEth, amount);
        borrower2.supply(cEth, amount);
        borrower2.borrow(cDai, amount / 2);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 1);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        (
            uint256 p2pSupplyRateBefore,
            uint256 p2pBorrowRateBefore,
            uint256 poolSupplyRateBefore,
            uint256 poolBorrowRateBefore
        ) = lens.getRatesPerBlock(cDai);

        hevm.roll(block.number + 1_000_000);

        (
            uint256 p2pSupplyRateAfter,
            uint256 p2pBorrowRateAfter,
            uint256 poolSupplyRateAfter,
            uint256 poolBorrowRateAfter
        ) = lens.getRatesPerBlock(cDai);

        assertEq(p2pSupplyRateBefore, p2pSupplyRateAfter);
        assertEq(p2pBorrowRateBefore, p2pBorrowRateAfter);
        assertEq(poolSupplyRateBefore, poolSupplyRateAfter);
        assertEq(poolBorrowRateBefore, poolBorrowRateAfter);
    }

    function testAverageSupplyRateShouldEqual0WhenNoSupply() public {
        (uint256 supplyRatePerBlock, uint256 p2pSupplyAmount, uint256 poolSupplyAmount) = lens
        .getAverageSupplyRatePerBlock(cDai);

        assertEq(supplyRatePerBlock, 0);
        assertEq(p2pSupplyAmount, 0);
        assertEq(poolSupplyAmount, 0);
    }

    function testAverageBorrowRateShouldEqual0WhenNoBorrow() public {
        (uint256 borrowRatePerBlock, uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = lens
        .getAverageBorrowRatePerBlock(cDai);

        assertEq(borrowRatePerBlock, 0);
        assertEq(p2pBorrowAmount, 0);
        assertEq(poolBorrowAmount, 0);
    }

    function testPoolSupplyAmountShouldBeEqualToPoolAmount() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        hevm.roll(block.number + 1_000_000);

        (, , uint256 poolSupplyAmount) = lens.getAverageSupplyRatePerBlock(cDai);

        assertEq(
            poolSupplyAmount,
            ICToken(cDai).balanceOf(address(morpho)).mul(ICToken(cDai).exchangeRateCurrent())
        );
    }

    function testPoolBorrowAmountShouldBeEqualToPoolAmount() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 1_000_000);

        (, , uint256 poolBorrowAmount) = lens.getAverageBorrowRatePerBlock(cDai);

        assertApproxEqAbs(
            poolBorrowAmount,
            ICToken(cDai).borrowBalanceCurrent(address(morpho)),
            1e4
        );
    }

    function testAverageSupplyRateShouldEqualPoolRateWhenNoMatch() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        (uint256 supplyRatePerBlock, uint256 p2pSupplyAmount, uint256 poolSupplyAmount) = lens
        .getAverageSupplyRatePerBlock(cDai);

        assertApproxEqAbs(supplyRatePerBlock, ICToken(cDai).supplyRatePerBlock(), 1);
        assertApproxEqAbs(poolSupplyAmount, amount, 1e9);
        assertEq(p2pSupplyAmount, 0);
    }

    function testAverageBorrowRateShouldEqualPoolRateWhenNoMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        (uint256 borrowRatePerBlock, uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = lens
        .getAverageBorrowRatePerBlock(cDai);

        assertApproxEqAbs(borrowRatePerBlock, ICToken(cDai).borrowRatePerBlock(), 1);
        assertApproxEqAbs(poolBorrowAmount, amount, 1);
        assertEq(p2pBorrowAmount, 0);
    }

    function testAverageRatesShouldEqualP2PRatesWhenFullyMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        (uint256 supplyRatePerBlock, uint256 p2pSupplyAmount, uint256 poolSupplyAmount) = lens
        .getAverageSupplyRatePerBlock(cDai);
        (uint256 borrowRatePerBlock, uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = lens
        .getAverageBorrowRatePerBlock(cDai);
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(supplyRatePerBlock, p2pSupplyRate, 1, "unexpected supply rate");
        assertApproxEqAbs(borrowRatePerBlock, p2pBorrowRate, 1, "unexpected borrow rate");
        assertApproxEqAbs(poolSupplyAmount, poolBorrowAmount, 1e9);
        assertApproxEqAbs(poolBorrowAmount, 0, 1e9);
        assertEq(p2pSupplyAmount, p2pBorrowAmount);
        assertApproxEqAbs(p2pBorrowAmount, amount, 1e9);
    }

    function testAverageSupplyRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        (uint256 supplyRatePerBlock, , ) = lens.getAverageSupplyRatePerBlock(cDai);
        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(supplyRatePerBlock, (p2pSupplyRate + poolSupplyRate) / 2, 1);
    }

    function testAverageBorrowRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(cDai, amount / 2);

        (uint256 borrowRatePerBlock, , ) = lens.getAverageBorrowRatePerBlock(cDai);
        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerBlock(cDai);

        assertApproxEqAbs(borrowRatePerBlock, (p2pBorrowRate + poolBorrowRate) / 2, 1);
    }

    function testAverageSupplyRateShouldEqualPoolRateWithFullSupplyDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cUsdc, to6Decimals(amount));

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(cUsdc, to6Decimals(amount));

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        borrower1.approve(usdc, type(uint256).max);
        borrower1.repay(cUsdc, type(uint256).max);

        (uint256 avgSupplyRate, , ) = lens.getAverageSupplyRatePerBlock(cUsdc);
        uint256 poolSupplyRate = ICToken(cUsdc).supplyRatePerBlock();

        assertApproxEqAbs(avgSupplyRate, poolSupplyRate, 2);
    }

    function testAverageBorrowRateShouldEqualPoolRateWithFullBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        hevm.roll(block.number + 100);

        supplier1.withdraw(cDai, type(uint256).max);

        (uint256 avgBorrowRate, , ) = lens.getAverageBorrowRatePerBlock(cDai);
        uint256 poolBorrowRate = ICToken(cDai).borrowRatePerBlock();

        assertApproxEqAbs(avgBorrowRate, poolBorrowRate, 1);
    }
}
