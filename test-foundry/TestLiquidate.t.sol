// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestLiquidate is TestSetup {
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
            vars.liquidationBonus) / (vars.borrowedTokenUnit * vars.collateralPrice * 10000);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        uint256 expectedOnPool = collateralOnPool -
            underlyingToScaledBalance(amountToSeize, normalizedIncome);

        testEquality(onPoolBorrower, expectedOnPool);
        assertEq(inP2PBorrower, 0);
    }

    // 5.3 - The liquidation is made of a Repay and Withdraw performed on a borrower's position on behalf of a liquidator.
    //       At most, the liquidator can liquidate 50% of the debt of a borrower and take the corresponding collateral (plus a bonus).
    //       Edge-cases here are at most the combination from part 3. and 4: Alice is matched with 4\*NMAX users on her collateral and her debt.
    //       She gets liquidated, the repay and withdraw are generating: first, NMAX `match supplier`, then NMAX `unmatch borrower` and for the
    //       withdraw NMAX `match borrower` and NMAX `unmatch supplier`.
    function test_liquidate_5_3() public {
        uint256 collateral = 100_000 ether;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        (, uint256 borrowedAmount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );
        borrower1.borrow(aDai, borrowedAmount);

        uint256 suppliedAmount = borrowedAmount;
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // NMAX borrowers have debt waiting on pool
        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount) / (2 * (NMAX - 1));
        uint256 amountPerBorrower = (borrowedAmount) / (2 * (NMAX - 1));

        for (uint256 i = 1; i < NMAX; i++) {
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getAssetPrice(usdc) * 93) / 100);

        // Liquidate
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), borrowedAmount / 2);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), borrowedAmount / 2);

        // Check borrower1 balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = p2pUnitToUnderlying(
            inP2PBorrower,
            borrowP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(expectedBorrowBalanceOnPool + expectedBorrowBalanceInP2P, borrowedAmount / 2);
    }

    // ----------

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        hevm.store(
            address(lendingPoolAddressesProvider),
            keccak256(abi.encode(bytes32("PRICE_ORACLE"), 2)),
            bytes32(uint256(uint160(address(customOracle))))
        );

        for (uint256 i = 0; i < pools.length; i++) {
            address underlying = IAToken(pools[i]).UNDERLYING_ASSET_ADDRESS();

            customOracle.setDirectPrice(underlying, oracle.getAssetPrice(underlying));
        }

        return customOracle;
    }
}
