// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestLiquidate is TestSetup {
    // 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function testShouldNotBePossibleToLiquidateUserAboveWater() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueNotAboveMax()"));
        liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);
    }

    // 5.2 - A user liquidates a borrower that has not enough collateral to cover for his debt.
    function testShouldLiquidateUser() public {
        uint256 collateral = 100_000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        (, uint256 amount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );
        borrower1.borrow(aDai, amount);

        (, uint256 collateralOnPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getAssetPrice(usdc) * 93) / 100);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );
        testEquality(expectedBorrowBalanceOnPool, amount / 2);
        assertEq(inP2PBorrower, 0);

        // Check borrower1 supply balance
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        PositionsManagerForAave.LiquidateVars memory vars;
        (
            vars.collateralReserveDecimals,
            ,
            ,
            vars.liquidationBonus,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(usdc);
        vars.collateralPrice = customOracle.getAssetPrice(usdc);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        (vars.borrowedReserveDecimals, , , , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(dai);
        vars.borrowedPrice = customOracle.getAssetPrice(dai);
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        uint256 amountToSeize = ((amount / 2) *
            vars.borrowedPrice *
            vars.collateralTokenUnit *
            vars.liquidationBonus) / (vars.borrowedTokenUnit * vars.collateralPrice * 10_000);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        uint256 expectedOnPool = collateralOnPool -
            underlyingToScaledBalance(amountToSeize, normalizedIncome);

        testEquality(onPoolBorrower, expectedOnPool);
        assertEq(inP2PBorrower, 0);
    }

    function testShouldLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(aUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(aDai, collateral);

        (, uint256 borrowerDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );
        (, uint256 supplierDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(supplier1),
            aDai
        );

        supplier1.borrow(aDai, supplierDebt);
        borrower1.borrow(aUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = positionsManager.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = positionsManager.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 2);
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(aUsdc, aDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = aDUnitToUnderlying(
            onPoolUsdc,
            lendingPool.getReserveNormalizedVariableDebt(usdc)
        ) +
            p2pUnitToUnderlying(inP2PUsdc, marketsManager.borrowP2PExchangeRate(aUsdc)) -
            toRepay;

        assertEq(onPoolBorrower, 0, "borrower borrow on pool");
        assertApproxEqAbs(
            p2pUnitToUnderlying(inP2PBorrower, marketsManager.borrowP2PExchangeRate(aUsdc)),
            expectedBorrowBalanceInP2P,
            1,
            "borrower borrow in P2P"
        );

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        PositionsManagerForAave.LiquidateVars memory vars;
        (
            vars.collateralReserveDecimals,
            ,
            ,
            vars.liquidationBonus,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(dai);
        vars.collateralPrice = customOracle.getAssetPrice(dai);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        (vars.borrowedReserveDecimals, , , , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(usdc);
        vars.borrowedPrice = customOracle.getAssetPrice(usdc);
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        uint256 amountToSeize = (toRepay *
            vars.borrowedPrice *
            vars.collateralTokenUnit *
            vars.liquidationBonus) / (vars.borrowedTokenUnit * vars.collateralPrice * 10_000);

        assertEq(
            onPoolBorrower,
            onPoolDai -
                underlyingToScaledBalance(
                    amountToSeize,
                    lendingPool.getReserveNormalizedIncome(dai)
                ),
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in P2P");
    }

    function testShouldPartiallyLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(aUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(aDai, collateral);

        (, uint256 borrowerDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );
        (, uint256 supplierDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(supplier1),
            aDai
        );

        supplier1.borrow(aDai, supplierDebt);
        borrower1.borrow(aUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = positionsManager.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = positionsManager.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 4);
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(aUsdc, aDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolUsdc,
            lendingPool.getReserveNormalizedVariableDebt(usdc)
        ) - toRepay;

        assertApproxEqAbs(
            aDUnitToUnderlying(onPoolBorrower, lendingPool.getReserveNormalizedVariableDebt(usdc)),
            expectedBorrowBalanceOnPool,
            1,
            "borrower borrow on pool"
        );
        assertEq(inP2PBorrower, inP2PUsdc, "borrower borrow in P2P");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        PositionsManagerForAave.LiquidateVars memory vars;
        (
            vars.collateralReserveDecimals,
            ,
            ,
            vars.liquidationBonus,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(dai);
        vars.collateralPrice = customOracle.getAssetPrice(dai);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        (vars.borrowedReserveDecimals, , , , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(usdc);
        vars.borrowedPrice = customOracle.getAssetPrice(usdc);
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        uint256 amountToSeize = (toRepay *
            vars.borrowedPrice *
            vars.collateralTokenUnit *
            vars.liquidationBonus) / (vars.borrowedTokenUnit * vars.collateralPrice * 10_000);

        assertEq(
            onPoolBorrower,
            onPoolDai -
                underlyingToScaledBalance(
                    amountToSeize,
                    lendingPool.getReserveNormalizedIncome(dai)
                ),
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in P2P");
    }

    function testFailLiquidateZero() public {
        positionsManager.liquidate(aDai, aDai, aDai, 0);
    }
}
