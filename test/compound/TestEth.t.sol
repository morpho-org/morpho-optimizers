// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestEth is TestSetup {
    using CompoundMath for uint256;

    function testSupplyEthOnPool() public {
        uint256 toSupply = 100 ether;

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(morpho), toSupply);
        supplier1.supply(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

        uint256 poolSupplyIndex = ICToken(cEth).exchangeRateCurrent();
        uint256 expectedOnPool = toSupply.div(poolSupplyIndex);

        testEquality(ERC20(cEth).balanceOf(address(morpho)), expectedOnPool, "balance of cToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cEth, address(supplier1));

        assertEq(inP2P, 0);
        testEquality(onPool, expectedOnPool);
        testEquality(balanceAfter, balanceBefore - toSupply);
    }

    function testSupplyEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        borrower1.approve(usdc, address(morpho), collateral);
        borrower1.supply(cUsdc, collateral);
        borrower1.borrow(cEth, toBorrow);

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(morpho), toSupply);
        supplier1.supply(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

        uint256 p2pSupplyIndex = lens.getCurrentP2PSupplyIndex(cEth);

        uint256 expectedInP2P = toSupply.div(p2pSupplyIndex);

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cEth, address(supplier1));

        assertEq(onPool, 0);
        testEquality(inP2P, expectedInP2P);
        testEquality(balanceAfter, balanceBefore - toSupply);
    }

    function testBorrowEthOnPool() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        borrower1.approve(usdc, address(morpho), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        borrower1.borrow(cEth, toBorrow);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cEth, address(borrower1));

        uint256 expectedOnPool = toSupply.div(ICToken(cEth).borrowIndex());

        testEquality(onPool, expectedOnPool);
        assertEq(inP2P, 0);
        testEquality(balanceAfter, balanceBefore + toBorrow);
    }

    function testBorrowEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;

        supplier1.approve(wEth, address(morpho), toSupply);
        supplier1.supply(cEth, toSupply);

        borrower1.approve(usdc, address(morpho), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 cEthIndex = ICToken(cEth).exchangeRateCurrent();
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        (, uint256 supplyOnPool) = morpho.supplyBalanceInOf(cEth, address(supplier1));
        uint256 toBorrow = supplyOnPool.mul(cEthIndex);
        borrower1.borrow(cEth, toBorrow);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

        uint256 expectedInP2P = toSupply.div(morpho.p2pBorrowIndex(cEth));

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cEth, address(borrower1));

        assertEq(onPool, 0);
        testEquality(inP2P, expectedInP2P);
        assertApproxEqAbs(balanceAfter, balanceBefore + toBorrow, 1e9);
    }

    function testWithdrawEthOnPool() public {
        uint256 toSupply = 1 ether;

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(morpho), toSupply);
        supplier1.supply(cEth, toSupply);

        supplier1.withdraw(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cEth, address(borrower1));

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        assertApproxEqAbs(balanceAfter, balanceBefore, 1e9);
    }

    function testWithdrawEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;

        uint256 balanceBefore = supplier1.balanceOf(wEth);
        supplier1.approve(wEth, address(morpho), toSupply);
        supplier1.supply(cEth, toSupply);

        borrower1.approve(usdc, collateral);
        borrower1.supply(cUsdc, collateral);
        borrower1.borrow(cEth, toBorrow);

        supplier1.withdraw(cEth, toSupply);
        uint256 balanceAfter = supplier1.balanceOf(wEth);

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cEth, address(borrower1));

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
        assertApproxEqAbs(balanceAfter, balanceBefore, 1e9);
    }

    function testRepayEthOnPool() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toBorrow = 1 ether;

        borrower1.approve(usdc, address(morpho), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        borrower1.borrow(cEth, toBorrow);

        moveOneBlockForwardBorrowRepay();

        borrower1.approve(wEth, address(morpho), toBorrow);
        borrower1.repay(cEth, toBorrow);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cEth, address(borrower1));

        testEqualityLarge(onPool, 0);
        testEquality(inP2P, 0);
        testEquality(balanceAfter, balanceBefore);
    }

    function testRepayEthInP2P() public {
        uint256 collateral = to6Decimals(100_000 ether);
        uint256 toSupply = 1 ether;
        uint256 toBorrow = 1 ether;
        uint256 toRepay = 1 ether;

        borrower1.approve(wEth, address(morpho), toSupply);
        borrower1.supply(cEth, toSupply);

        borrower1.approve(usdc, address(morpho), collateral);
        borrower1.supply(cUsdc, collateral);
        uint256 balanceBefore = borrower1.balanceOf(wEth);
        borrower1.borrow(cEth, toBorrow);

        moveOneBlockForwardBorrowRepay();

        borrower1.approve(wEth, address(morpho), toRepay);
        borrower1.repay(cEth, toRepay);
        uint256 balanceAfter = borrower1.balanceOf(wEth);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cEth, address(borrower1));

        assertApproxEqAbs(onPool, 0, 1e2);
        assertApproxEqAbs(inP2P, 0, 1e2);
        assertApproxEqAbs(balanceAfter, balanceBefore, 1e9, "balance");
    }

    function testShouldLiquidateUserWithEthBorrowed() public {
        uint256 collateral = to6Decimals(100_000 ether);

        // supplier1 supplies surplus of USDC to put Morpho clearly above water.
        supplier1.approve(usdc, address(morpho), collateral);
        supplier1.supply(cUsdc, collateral);

        borrower1.approve(usdc, address(morpho), collateral);
        borrower1.supply(cUsdc, collateral);

        (, uint256 amount) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cEth);
        borrower1.borrow(cEth, amount);

        (, uint256 collateralOnPool) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));

        moveOneBlockForwardBorrowRepay();

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getUnderlyingPrice(cUsdc) * 95) / 100);

        // Liquidate.
        uint256 toRepay = (amount * 1) / 3;
        User liquidator = borrower3;
        uint256 balanceBefore = liquidator.balanceOf(wEth);

        liquidator.approve(wEth, address(morpho), toRepay);
        liquidator.liquidate(cEth, cUsdc, address(borrower1), toRepay);
        uint256 balanceAfter = liquidator.balanceOf(wEth);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cEth,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = (amount - toRepay).div(ICToken(cEth).borrowIndex());
        testEqualityLarge(onPoolBorrower, expectedBorrowBalanceOnPool, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in peer-to-peer");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cUsdc);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cEth);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            amountToSeize.div(ICToken(cUsdc).exchangeRateCurrent());

        testEquality(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        testEquality(balanceAfter, balanceBefore - toRepay, "amount seized");
        assertEq(inP2PBorrower, 0, "borrower supply in peer-to-peer");
    }

    function testShouldLiquidateUserWithEthAsCollateral() public {
        uint256 collateral = 1 ether;
        uint256 toSupplyMore = to6Decimals(100_000 ether);

        // supplier1 supplies surplus of USDC to put Morpho clearly above water.
        supplier1.approve(usdc, address(morpho), toSupplyMore);
        supplier1.supply(cUsdc, toSupplyMore);

        borrower1.approve(wEth, address(morpho), collateral);
        borrower1.supply(cEth, collateral);

        (, uint256 amount) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);
        borrower1.borrow(cDai, amount);

        (, uint256 collateralOnPool) = morpho.supplyBalanceInOf(cEth, address(borrower1));

        moveOneBlockForwardBorrowRepay();

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 105) / 100);

        // Liquidate.
        uint256 toRepay = (amount * 1) / 3;
        User liquidator = borrower3;
        uint256 balanceBefore = liquidator.balanceOf(wEth);
        liquidator.approve(dai, address(morpho), toRepay);
        liquidator.liquidate(cDai, cEth, address(borrower1), toRepay);
        uint256 balanceAfter = liquidator.balanceOf(wEth);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = (amount - toRepay).div(ICToken(cDai).borrowIndex());
        testEqualityLarge(onPoolBorrower, expectedBorrowBalanceOnPool, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in peer-to-peer");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cEth, address(borrower1));

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cEth);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            amountToSeize.div(ICToken(cEth).exchangeRateCurrent());

        testEquality(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        testEquality(balanceAfter, balanceBefore + amountToSeize, "amount seized");
        assertEq(inP2PBorrower, 0, "borrower supply in peer-to-peer");
    }

    function testShouldGetEthMarketConfiguration() public {
        (address underlying, , , , , , , ) = lens.getMarketConfiguration(cEth);

        assertEq(underlying, wEth);
    }
}
