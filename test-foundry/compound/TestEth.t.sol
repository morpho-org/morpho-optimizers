// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestEth is TestSetup {
    using CompoundMath for uint256;

    function testSupplyEthOnPool() public {
        uint256 toSupply = 100 ether;

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(positionsManager), toSupply);
        supplier1.supply(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

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

        borrower1.approve(usdc, address(positionsManager), collateral);
        borrower1.supply(cUsdc, collateral);
        borrower1.borrow(cEth, toBorrow);

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(positionsManager), toSupply);
        supplier1.supply(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

        (uint256 supplyP2PExchangeRate, ) = marketsManager.getUpdatedP2PExchangeRates(cEth);

        uint256 expectedInP2P = toSupply.div(supplyP2PExchangeRate);

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

        borrower1.approve(usdc, address(positionsManager), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        borrower1.borrow(cEth, toBorrow);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

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

        supplier1.approve(wEth, address(positionsManager), toSupply);
        supplier1.supply(cEth, toSupply);

        borrower1.approve(usdc, address(positionsManager), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        borrower1.borrow(cEth, toBorrow);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

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

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(positionsManager), toSupply);
        supplier1.supply(cEth, toSupply);

        supplier1.withdraw(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

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

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(positionsManager), toSupply);
        supplier1.supply(cEth, toSupply);

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        borrower1.borrow(cEth, toBorrow);

        supplier1.withdraw(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

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

        borrower1.approve(usdc, address(positionsManager), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        borrower1.borrow(cEth, toBorrow);

        borrower1.approve(wEth, address(positionsManager), toBorrow);
        borrower1.repay(cEth, toBorrow);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        testEquality(balanceAfter, balanceBefore);
    }

    function testRepayEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;
        uint256 toRepay = 1 ether;

        borrower1.approve(wEth, address(positionsManager), toSupply);
        borrower1.supply(cEth, toSupply);

        borrower1.approve(usdc, address(positionsManager), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        borrower1.borrow(cEth, toBorrow);

        borrower1.approve(wEth, address(positionsManager), toRepay);
        borrower1.repay(cEth, toRepay);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        assertApproxEq(balanceAfter, balanceBefore, 1e9, "balance");
    }

    function testShouldLiquidateUserWithEthBorrowed() public {
        uint256 collateral = to6Decimals(100_000 ether);

        // supplier1 supplies excedent of USDC to put Morpho clearly above water.
        supplier1.approve(usdc, address(positionsManager), collateral);
        supplier1.supply(cUsdc, collateral);

        borrower1.approve(usdc, address(positionsManager), collateral);
        borrower1.supply(cUsdc, collateral);

        (, uint256 amount) = morphoLens.getUserMaxCapacitiesForAsset(address(borrower1), cEth);
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
        uint256 balanceBefore = liquidator.balanceOf(wEth);

        liquidator.approve(wEth, address(positionsManager), toRepay);
        liquidator.liquidate(cEth, cUsdc, address(borrower1), toRepay);
        uint256 balanceAfter = liquidator.balanceOf(wEth);

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

        // supplier1 supplies excedent of USDC to put Morpho clearly above water.
        supplier1.approve(usdc, address(positionsManager), toSupplyMore);
        supplier1.supply(cUsdc, toSupplyMore);

        borrower1.approve(wEth, address(positionsManager), collateral);
        borrower1.supply(cEth, collateral);

        (, uint256 amount) = morphoLens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);
        borrower1.borrow(cDai, amount);

        (, uint256 collateralOnPool) = positionsManager.supplyBalanceInOf(cEth, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 105) / 100);

        // Liquidate.
        uint256 toRepay = (amount * 1) / 3;
        User liquidator = borrower3;
        uint256 balanceBefore = liquidator.balanceOf(wEth);
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(cDai, cEth, address(borrower1), toRepay);
        uint256 balanceAfter = liquidator.balanceOf(wEth);

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
