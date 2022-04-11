// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestEth is TestSetup {
    using CompoundMath for uint256;

    function testSupplyEthOnPool() public {
        uint256 toSupply = 100 ether;

        payable(address(supplier1)).transfer(toSupply * 10);
        uint256 balanceBefore = address(supplier1).balance;
        hevm.prank(address(supplier1));
        positionsManager.supply{value: toSupply}(cEth, 0, 0);
        uint256 balanceAfter = address(supplier1).balance;

        uint256 supplyPoolIndex = ICToken(cEth).exchangeRateCurrent();
        uint256 expectedOnPool = toSupply.div(supplyPoolIndex);

        assertEq(
            IERC20(cEth).balanceOf(address(positionsManager)),
            expectedOnPool,
            "balance of cToken"
        );

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            cEth,
            address(supplier1)
        );

        assertEq(inP2P, 0);
        assertEq(onPool, expectedOnPool);
        assertEq(balanceAfter, balanceBefore - toSupply);
    }

    function testSupplyEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        borrower1.borrow(cEth, toBorrow);

        payable(address(supplier1)).transfer(toSupply);
        uint256 balanceBefore = address(supplier1).balance;
        hevm.prank(address(supplier1));
        positionsManager.supply{value: toSupply}(cEth, 0, 0);
        uint256 balanceAfter = address(supplier1).balance;

        uint256 expectedInP2P = toSupply.div(marketsManager.getUpdatedSupplyP2PExchangeRate(cEth));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            cEth,
            address(supplier1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, expectedInP2P);
        assertEq(balanceAfter, balanceBefore - toSupply);
    }

    function testBorrowEthOnPool() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = address(borrower1).balance;
        borrower1.borrow(cEth, toBorrow);
        uint256 balanceAfter = address(borrower1).balance;

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );

        uint256 expectedOnPool = toSupply.div(ICToken(cEth).borrowIndex());

        assertEq(onPool, expectedOnPool);
        assertEq(inP2P, 0);
        assertEq(balanceAfter, balanceBefore + toBorrow);
    }

    function testBorrowEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        payable(address(supplier1)).transfer(toSupply * 10);
        hevm.prank(address(supplier1));
        positionsManager.supply{value: toSupply}(cEth, 0, 0);

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = address(borrower1).balance;
        borrower1.borrow(cEth, toBorrow);
        uint256 balanceAfter = address(borrower1).balance;

        uint256 expectedInP2P = toSupply.div(marketsManager.borrowP2PExchangeRate(cEth));

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, expectedInP2P);
        assertApproxEq(balanceAfter, balanceBefore + toBorrow, 1e9);
    }

    function testWithdrawEthOnPool() public {
        uint256 toSupply = 1 ether;

        payable(address(supplier1)).transfer(toSupply * 10);
        uint256 balanceBefore = address(supplier1).balance;
        hevm.prank(address(supplier1));
        positionsManager.supply{value: toSupply}(cEth, 0, 0);

        hevm.prank(address(supplier1));
        positionsManager.withdraw(cEth, toSupply);
        uint256 balanceAfter = address(supplier1).balance;

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            cEth,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        assertApproxEq(balanceAfter, balanceBefore, 1e9);
    }

    function testWithdrawEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        payable(address(supplier1)).transfer(toSupply * 10);
        uint256 balanceBefore = address(supplier1).balance;
        hevm.prank(address(supplier1));
        positionsManager.supply{value: toSupply}(cEth, 0, 0);

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        borrower1.borrow(cEth, toBorrow);

        hevm.prank(address(supplier1));
        positionsManager.withdraw(cEth, toSupply);
        uint256 balanceAfter = address(supplier1).balance;

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            cEth,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        assertApproxEq(balanceAfter, balanceBefore, 1e9);
    }

    function testRepayEthOnPool() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toBorrow = 1 ether;

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = address(borrower1).balance;
        borrower1.borrow(cEth, toBorrow);

        hevm.prank(address(borrower1));
        positionsManager.repay{value: toBorrow}(cEth, 0);
        uint256 balanceAfter = address(borrower1).balance;

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        assertEq(balanceAfter, balanceBefore);
    }

    function testRepayEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        payable(address(supplier1)).transfer(toSupply * 10);
        hevm.prank(address(supplier1));
        positionsManager.supply{value: toSupply}(cEth, 0, 0);

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = address(borrower1).balance;
        borrower1.borrow(cEth, toBorrow);

        payable(address(borrower1)).transfer(toBorrow - address(borrower1).balance);
        hevm.prank(address(borrower1));
        positionsManager.repay{value: 1 ether}(cEth, 0);
        uint256 balanceAfter = address(borrower1).balance;

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        assertEq(balanceAfter, balanceBefore, "balance");
    }
}
