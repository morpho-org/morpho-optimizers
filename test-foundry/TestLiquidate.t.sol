// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./utils/TestSetup.sol";

contract TestLiquidate is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    // 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function test_liquidate_5_1() public {
        uint256 amount = 10000 ether;
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
    function test_liquidate_5_2() public {
        uint256 collateral = 100 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        (, uint256 amount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );
        mineBlocks(1);
        borrower1.borrow(aDai, amount);
        mineBlocks(1);

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
            pool.getReserveNormalizedVariableDebt(dai)
        );
        assertApproxEq(expectedBorrowBalanceOnPool, amount / 2, 1e15);
        assertApproxEq(inP2PBorrower, 0, 1e15);

        // Check borrower1 supply balance
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        PositionsManagerForAave.LiquidateVars memory vars;
        (, , vars.liquidationBonus, vars.collateralReserveDecimals, , ) = pool
        .getConfiguration(usdc)
        .getParams();
        vars.collateralPrice = customOracle.getAssetPrice(usdc);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        (, , , vars.borrowedReserveDecimals, , ) = pool.getConfiguration(dai).getParams();
        vars.borrowedPrice = customOracle.getAssetPrice(dai);
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        uint256 amountToSeize = ((amount / 2) *
            vars.borrowedPrice *
            vars.collateralTokenUnit *
            vars.liquidationBonus) / (vars.borrowedTokenUnit * vars.collateralPrice * 10000);

        uint256 normalizedIncome = pool.getReserveNormalizedIncome(usdc);
        uint256 expectedOnPool = collateralOnPool -
            underlyingToScaledBalance(amountToSeize, normalizedIncome);

        assertApproxEq(onPoolBorrower, expectedOnPool, 1e15);
        assertApproxEq(inP2PBorrower, 0, 1e15);
    }
}
