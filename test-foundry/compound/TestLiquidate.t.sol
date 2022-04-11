// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestLiquidate is TestSetup {
    using CompoundMath for uint256;

    // 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function testShouldNotBePossibleToLiquidateUserAboveWater() public {
        uint256 amount = 10_000 ether;
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
    function testShouldLiquidateUser() public {
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

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getUnderlyingPrice(cUsdc) * 94) / 100);

        // Liquidate.
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = toRepay.div(ICToken(cDai).borrowIndex());
        assertApproxEq(onPoolBorrower, expectedBorrowBalanceOnPool, 5, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in P2P");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cUsdc);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            underlyingToPoolSupplyBalance(amountToSeize, ICToken(cUsdc).exchangeRateCurrent());

        assertEq(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        assertEq(inP2PBorrower, 0, "borrower supply in P2P");
    }

    function testFailLiquidateZero() public {
        positionsManager.liquidate(cDai, cDai, cDai, 0);
    }
}
