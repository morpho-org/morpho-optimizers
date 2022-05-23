// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestLiquidate is TestSetup {
    using CompoundMath for uint256;

    // A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function testShouldNotBePossibleToLiquidateUserAboveWater() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, address(morpho), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(morpho), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedLiquidate()"));
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);
    }

    // A user liquidates a borrower that has not enough collateral to cover for his debt.
    function testShouldLiquidateUser() public {
        uint256 collateral = 100_000 ether;

        borrower1.approve(usdc, address(morpho), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        (, uint256 amount) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);
        borrower1.borrow(cDai, amount);

        (, uint256 collateralOnPool) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getUnderlyingPrice(cUsdc) * 94) / 100);

        // Liquidate.
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(morpho), toRepay);
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = toRepay.div(ICToken(cDai).borrowIndex());
        assertApproxEq(onPoolBorrower, expectedBorrowBalanceOnPool, 5, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in peer-to-peer");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cUsdc);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            amountToSeize.div(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        assertEq(inP2PBorrower, 0, "borrower supply in peer-to-peer");
    }

    function testShouldLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(cUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(cDai, collateral);

        (, uint256 borrowerDebt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdc);
        (, uint256 supplierDebt) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cDai);

        supplier1.borrow(cDai, supplierDebt);
        borrower1.borrow(cUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 94) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 2) - 1; // -1 because of rounding error related to compound's approximation
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(cUsdc, cDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = onPoolUsdc.mul(ICToken(cUsdc).borrowIndex()) +
            inP2PUsdc.mul(morpho.p2pBorrowIndex(cUsdc)) -
            (borrowerDebt / 2);

        assertEq(onPoolBorrower, 0, "borrower borrow on pool");
        assertApproxEq(
            inP2PBorrower.mul(morpho.p2pBorrowIndex(cUsdc)),
            expectedBorrowBalanceInP2P,
            2,
            "borrower borrow in peer-to-peer"
        );

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(customOracle.getUnderlyingPrice(cUsdc))
        .div(customOracle.getUnderlyingPrice(cDai));

        assertEq(
            onPoolBorrower,
            onPoolDai - amountToSeize.div(ICToken(cDai).exchangeRateCurrent()),
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in peer-to-peer");
    }

    function testShouldPartiallyLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(cUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(cDai, collateral);

        (, uint256 borrowerDebt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdc);
        (, uint256 supplierDebt) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cDai);

        supplier1.borrow(cDai, supplierDebt);
        borrower1.borrow(cUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 94) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 4);
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(cUsdc, cDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceOnPool = onPoolUsdc.mul(ICToken(cUsdc).borrowIndex()) -
            toRepay;

        assertApproxEq(
            onPoolBorrower.mul(ICToken(cUsdc).borrowIndex()),
            expectedBorrowBalanceOnPool,
            1,
            "borrower borrow on pool"
        );
        assertEq(inP2PBorrower, inP2PUsdc, "borrower borrow in peer-to-peer");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(customOracle.getUnderlyingPrice(cUsdc))
        .div(customOracle.getUnderlyingPrice(cDai));

        assertEq(
            onPoolBorrower,
            onPoolDai - amountToSeize.div(ICToken(cDai).exchangeRateCurrent()),
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in peer-to-peer");
    }

    function testFailLiquidateZero() public {
        morpho.liquidate(cDai, cDai, cDai, 0);
    }
}
