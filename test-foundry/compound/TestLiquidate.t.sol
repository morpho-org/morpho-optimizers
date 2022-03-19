// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestLiquidate is TestSetup {
    using CompoundMath for uint256;

    // 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function test_liquidate_5_1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueNotAboveMax()"));
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);
    }

    // 5.2 - A user liquidates a borrower that has not enough collateral to cover for his debt.
    function test_liquidate_5_2() public {
        uint256 collateral = 100_000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        (, uint256 amount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );
        borrower1.borrow(cDai, amount);

        (, uint256 collateralOnPool) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getUnderlyingPrice(cUsdc) * 93) / 100);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = debtUnitToUnderlying(
            onPoolBorrower,
            ICToken(cDai).exchangeRateCurrent()
        );
        testEquality(expectedBorrowBalanceOnPool, amount / 2);
        assertEq(inP2PBorrower, 0);

        // Check borrower1 supply balance
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 collateralPrice = customOracle.getAssetPrice(cUsdc);
        uint256 borrowedPrice = customOracle.getAssetPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            underlyingToPoolSupplyBalance(amountToSeize, ICToken(cUsdc).exchangeRateCurrent());

        testEquality(onPoolBorrower, expectedOnPool);
        assertEq(inP2PBorrower, 0);
    }
}
