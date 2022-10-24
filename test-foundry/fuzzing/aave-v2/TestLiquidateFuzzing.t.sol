// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetupFuzzing.sol";

contract TestLiquidateFuzzing is TestSetupFuzzing {
    struct addressVars {
        address collateralAsset;
        address collateralUnderlying;
        address suppliedAsset;
        address suppliedUnderlying;
        address borrowedAsset;
        address borrowedUnderlying;
    }

    // Should not be able to liquidate a user with enough collateral.
    function testLiquidate1Fuzzed(
        uint128 _amountSupplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _firstModulo,
        uint8 _secondModulo
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getSupplyAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 amountSupplied = getSupplyAmount(suppliedUnderlying, _amountSupplied);
        hevm.assume(_firstModulo != 0);
        hevm.assume(_secondModulo != 0);

        borrower1.approve(suppliedUnderlying, amountSupplied);
        borrower1.supply(suppliedAsset, amountSupplied);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );
        uint256 borrowedAmount = (borrowable * _firstModulo) / 255;

        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);

        // Liquidate
        uint256 toRepay = ((borrowedAmount / 2) * _secondModulo) / 255;
        assumeLiquidateAmountIsCorrect(toRepay);

        User liquidator = borrower3;
        liquidator.approve(borrowedUnderlying, address(morpho), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedLiquidate()"));
        liquidator.liquidate(borrowedAsset, suppliedAsset, address(borrower1), toRepay);
    }
}
