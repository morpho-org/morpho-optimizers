// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestLiquidate is TestSetup {
    // A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function testShouldNotBePossibleToLiquidateUserAboveWater() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, address(morpho), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(morpho), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedLiquidate()"));
        liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);
    }

    // A user liquidates a borrower that has not enough collateral to cover for his debt.
    function testShouldLiquidateUser() public {
        uint256 collateral = 100_000 ether;

        borrower1.approve(usdc, address(morpho), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        (, uint256 amount) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);
        borrower1.borrow(aDai, amount);

        (, uint256 collateralOnPool) = morpho.supplyBalanceInOf(aUsdc, address(borrower1));

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getAssetPrice(usdc) * 93) / 100);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(morpho), toRepay);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            pool.getReserveNormalizedVariableDebt(dai)
        );
        testEquality(expectedBorrowBalanceOnPool, toRepay);
        assertEq(inP2PBorrower, 0);

        // Check borrower1 supply balance
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(aUsdc, address(borrower1));

        ExitManager.LiquidateVars memory vars;
        (, , vars.liquidationBonus, vars.collateralReserveDecimals, , ) = pool
        .protocolDataProvider
        .getConfiguration(usdc)
        .getParams();
        uint256 collateralPrice = customOracle.getAssetPrice(usdc);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        {
            (, , , vars.borrowedReserveDecimals, , ) = pool
            .protocolDataProvider
            .getConfiguration(dai)
            .getParams();
            uint256 borrowedPrice = customOracle.getAssetPrice(dai);
            vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

            uint256 amountToSeize = (toRepay *
                borrowedPrice *
                vars.collateralTokenUnit *
                vars.liquidationBonus) / (vars.borrowedTokenUnit * collateralPrice * 10_000);

            uint256 normalizedIncome = pool.getReserveNormalizedIncome(usdc);
            uint256 expectedOnPool = collateralOnPool -
                underlyingToScaledBalance(amountToSeize, normalizedIncome);

            testEquality(onPoolBorrower, expectedOnPool);
            assertEq(inP2PBorrower, 0);
        }
    }

    function testShouldLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(aUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(aDai, collateral);

        (, uint256 borrowerDebt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aUsdc);
        (, uint256 supplierDebt) = lens.getUserMaxCapacitiesForAsset(address(supplier1), aDai);

        supplier1.borrow(aDai, supplierDebt);
        borrower1.borrow(aUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = morpho.supplyBalanceInOf(aDai, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 2);
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(aUsdc, aDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = aDUnitToUnderlying(
            onPoolUsdc,
            pool.getReserveNormalizedVariableDebt(usdc)
        ) +
            p2pUnitToUnderlying(inP2PUsdc, morpho.p2pBorrowIndex(aUsdc)) -
            toRepay;

        assertApproxEq(onPoolBorrower, 0, 1, "borrower borrow on pool");
        assertApproxEq(
            p2pUnitToUnderlying(inP2PBorrower, morpho.p2pBorrowIndex(aUsdc)),
            expectedBorrowBalanceInP2P,
            1,
            "borrower borrow in peer-to-peer"
        );

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(aDai, address(borrower1));

        ExitManager.LiquidateVars memory vars;
        (, , vars.liquidationBonus, vars.collateralReserveDecimals, , ) = pool
        .protocolDataProvider
        .getConfiguration(dai)
        .getParams();
        uint256 collateralPrice = customOracle.getAssetPrice(dai);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        (, , vars.liquidationBonus, vars.borrowedReserveDecimals, , ) = pool
        .protocolDataProvider
        .getConfiguration(usdc)
        .getParams();
        uint256 borrowedPrice = customOracle.getAssetPrice(usdc);
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        uint256 amountToSeize = (toRepay *
            borrowedPrice *
            vars.collateralTokenUnit *
            vars.liquidationBonus) / (vars.borrowedTokenUnit * collateralPrice * 10_000);

        assertApproxEq(
            onPoolBorrower,
            onPoolDai -
                underlyingToScaledBalance(amountToSeize, pool.getReserveNormalizedIncome(dai)),
            1,
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in peer-to-peer");
    }

    function testShouldPartiallyLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(aUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(aDai, collateral);

        (, uint256 borrowerDebt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aUsdc);
        (, uint256 supplierDebt) = lens.getUserMaxCapacitiesForAsset(address(supplier1), aDai);

        supplier1.borrow(aDai, supplierDebt);
        borrower1.borrow(aUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = morpho.supplyBalanceInOf(aDai, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 4);
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(aUsdc, aDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolUsdc,
            pool.getReserveNormalizedVariableDebt(usdc)
        ) - toRepay;

        assertApproxEq(
            aDUnitToUnderlying(onPoolBorrower, pool.getReserveNormalizedVariableDebt(usdc)),
            expectedBorrowBalanceOnPool,
            1,
            "borrower borrow on pool"
        );
        assertEq(inP2PBorrower, inP2PUsdc, "borrower borrow in peer-to-peer");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(aDai, address(borrower1));

        ExitManager.LiquidateVars memory vars;
        (, , vars.liquidationBonus, vars.collateralReserveDecimals, , ) = pool
        .protocolDataProvider
        .getConfiguration(dai)
        .getParams();
        uint256 collateralPrice = customOracle.getAssetPrice(dai);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        (, , , vars.borrowedReserveDecimals, , ) = pool
        .protocolDataProvider
        .getConfiguration(usdc)
        .getParams();
        uint256 borrowedPrice = customOracle.getAssetPrice(usdc);
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        uint256 amountToSeize = (toRepay *
            borrowedPrice *
            vars.collateralTokenUnit *
            vars.liquidationBonus) / (vars.borrowedTokenUnit * collateralPrice * 10_000);

        testEquality(
            onPoolBorrower,
            onPoolDai -
                underlyingToScaledBalance(amountToSeize, pool.getReserveNormalizedIncome(dai)),
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in peer-to-peer");
    }

    function testFailLiquidateZero() public {
        morpho.liquidate(aDai, aDai, aDai, 0);
    }
}
