// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestLiquidate is TestSetup {
    // 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function test_liquidate_5_1(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        // Liquidate
        uint256 toRepay = borrow.amount / 2;
        User liquidator = borrower3;
        liquidator.approve(borrow.underlying, address(positionsManager), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueNotAboveMax()"));
        liquidator.liquidate(borrow.poolToken, supply.poolToken, address(borrower1), toRepay);
    }

    // 5.2 - A user liquidates a borrower that has not enough collateral to cover for his debt.
    function test_liquidate_5_2(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        (, uint256 collateralOnPool) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(borrower1)
        );

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(
            supply.underlying,
            (oracle.getAssetPrice(supply.underlying) * 90) / 100
        );

        // Liquidate
        uint256 toRepay = borrow.amount / 2;
        User liquidator = borrower3;
        liquidator.approve(borrow.underlying, toRepay);
        liquidator.liquidate(borrow.poolToken, supply.poolToken, address(borrower1), toRepay);

        // Check borrower1 borrow balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
        );
        testEquality(expectedBorrowBalanceOnPool, borrow.amount / 2);
        assertEq(inP2PBorrower, 0);

        // Check borrower1 supply balance
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
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

        ) = protocolDataProvider.getReserveConfigurationData(supply.underlying);
        vars.collateralPrice = customOracle.getAssetPrice(supply.underlying);
        vars.collateralTokenUnit = 10**vars.collateralReserveDecimals;

        (vars.borrowedReserveDecimals, , , , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(borrow.underlying);
        vars.borrowedPrice = customOracle.getAssetPrice(borrow.underlying);
        vars.borrowedTokenUnit = 10**vars.borrowedReserveDecimals;

        uint256 amountToSeize = ((borrow.amount / 2) *
            vars.borrowedPrice *
            vars.collateralTokenUnit *
            vars.liquidationBonus) / (vars.borrowedTokenUnit * vars.collateralPrice * 10000);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(supply.underlying);
        uint256 expectedOnPool = collateralOnPool -
            underlyingToScaledBalance(amountToSeize, normalizedIncome);

        testEquality(onPoolBorrower, expectedOnPool);
        assertEq(inP2PBorrower, 0);
    }

    // 5.3 - The liquidation is made of a Repay and Withdraw performed on a borrower's position on behalf of a liquidator.
    //       At most, the liquidator can liquidate 50% of the debt of a borrower and take the corresponding collateral (plus a bonus).
    //       Edge-cases here are at most the combination from part 3. and 4. called with the previous amount.
    function test_liquidate_5_3(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        // Borrower1 & supplier1 are matched for borrow.amount
        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        // NMAX borrowers have debt waiting on pool
        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        uint256 amountPerSupplier = (borrow.amount) / (2 * (NMAX - 1));
        uint256 amountPerBorrower = (supply.amount) / (2 * (NMAX - 1));
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(borrow.underlying, amountPerSupplier);
            suppliers[i].supply(borrow.poolToken, amountPerSupplier);

            borrowers[i].approve(supply.underlying, supply.amount);
            borrowers[i].supply(supply.poolToken, supply.amount);
            borrowers[i].borrow(borrow.poolToken, amountPerBorrower);
        }

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(
            supply.underlying,
            (oracle.getAssetPrice(supply.underlying) * 90) / 100
        );

        // Liquidate
        User liquidator = borrower3;
        liquidator.approve(borrow.underlying, address(positionsManager), borrow.amount / 2);
        liquidator.liquidate(
            borrow.poolToken,
            supply.poolToken,
            address(borrower1),
            borrow.amount / 2
        );

        // Check borrower1 balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(borrow.poolToken);
        uint256 expectedBorrowBalanceInP2P = p2pUnitToUnderlying(
            inP2PBorrower,
            borrowP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(expectedBorrowBalanceOnPool + expectedBorrowBalanceInP2P, borrow.amount / 2);
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
