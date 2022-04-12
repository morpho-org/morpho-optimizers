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

    function testShouldLiquidateUserWithEthBorrowed() public {
        uint256 collateral = to6Decimals(100_000 ether);

        // supplier1 suppliers excedent of USDC to put Morpho clearly above water.
        supplier1.approve(usdc, address(positionsManager), collateral);
        supplier1.supply(cUsdc, collateral);

        borrower1.approve(usdc, address(positionsManager), collateral);
        borrower1.supply(cUsdc, collateral);

        (, uint256 amount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cEth
        );
        borrower1.borrow(cEth, amount);

        (, uint256 collateralOnPool) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getUnderlyingPrice(cUsdc) * 95) / 100);

        // Liquidate.
        uint256 toRepay = (amount * 1) / 3;
        User liquidator = borrower3;
        payable(address(liquidator)).transfer(toRepay * 10);
        uint256 balanceBefore = address(liquidator).balance;
        hevm.prank(address(liquidator));
        positionsManager.liquidate{value: toRepay}(cEth, cUsdc, address(borrower1), 0);
        uint256 balanceAfter = address(liquidator).balance;

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = (amount - toRepay).div(ICToken(cEth).borrowIndex());
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in P2P");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cUsdc);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cEth);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            amountToSeize.div(ICToken(cUsdc).exchangeRateCurrent());

        testEquality(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        assertEq(balanceAfter, balanceBefore - toRepay, "amount seized");
        assertEq(inP2PBorrower, 0, "borrower supply in P2P");
    }

    function testShouldLiquidateUserWithEthAsCollateral() public {
        uint256 collateral = 1 ether;
        uint256 toSupplyMore = to6Decimals(100_000 ether);

        // supplier1 suppliers excedent of USDC to put Morpho clearly above water.
        supplier1.approve(usdc, address(positionsManager), toSupplyMore);
        supplier1.supply(cUsdc, toSupplyMore);

        payable(address(borrower1)).transfer(collateral * 10);
        hevm.prank(address(borrower1));
        positionsManager.supply{value: collateral}(cEth, 0, 0);

        (, uint256 amount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );
        borrower1.borrow(cDai, amount);

        (, uint256 collateralOnPool) = positionsManager.supplyBalanceInOf(cEth, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 105) / 100);

        // Liquidate.
        uint256 toRepay = (amount * 1) / 3;
        User liquidator = borrower3;
        uint256 balanceBefore = address(liquidator).balance;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(cDai, cEth, address(borrower1), toRepay);
        uint256 balanceAfter = address(liquidator).balance;

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = (amount - toRepay).div(ICToken(cDai).borrowIndex());
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in P2P");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            cEth,
            address(borrower1)
        );

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cEth);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            amountToSeize.div(ICToken(cEth).exchangeRateCurrent());

        testEquality(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        assertEq(balanceAfter, balanceBefore + amountToSeize, "amount seized");
        assertEq(inP2PBorrower, 0, "borrower supply in P2P");
    }
}
