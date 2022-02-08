// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetupAdapters.sol";

contract TestFlashSwapLiquidator is TestSetupAdapters {
    // 5.1 - A user liquidates a borrower using a flash loan.
    function test_liquidate_5_8() public {
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
        flashSwapLiquidator.liquidate(
            address(borrower1),
            aDai,
            aUsdc,
            toRepay,
            1000,
            address(liquidator)
        );

        // Check borrower1 borrow balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );
        //testEquality(expectedBorrowBalanceOnPool, amount / 2);
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

        //assert(onPoolBorrower, expectedOnPool);
        assertEq(inP2PBorrower, 0);
    }

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
