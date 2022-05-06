// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

contract TestLiquidateFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    // Should not be able to liquidate a user with enough collateral.
    function testLiquidate1Fuzzed(
        uint128 _amountSupplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _firstModulo,
        uint8 _secondModulo
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;

        // Because this is a Liquidation Test, we need to make sure that the supplied amount is enough
        // To obtain a non zero borrow & liquidation amount.
        console.log(10**ERC20(suppliedUnderlying).decimals());
        hevm.assume(amountSupplied > 10**ERC20(suppliedUnderlying).decimals());
        hevm.assume(_firstModulo != 0);
        hevm.assume(_secondModulo != 0);
        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountSupplied);

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

    function testLiquidate2Fuzzed(
        uint128 _amountSupplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _randomModulo
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;

        // Because this is a Liquidation Test, we need to make sure that the supplied amount is enough
        // To obtain a non zero borrow & liquidation amount.
        console.log(10**ERC20(suppliedUnderlying).decimals());
        hevm.assume(amountSupplied > 10**ERC20(suppliedUnderlying).decimals());
        hevm.assume(_randomModulo != 0);
        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountSupplied);

        borrower1.approve(suppliedUnderlying, amountSupplied);
        borrower1.supply(suppliedAsset, amountSupplied);

        (, uint256 borrowedAmount) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(
            suppliedUnderlying,
            (oracle.getUnderlyingPrice(suppliedAsset) * 94) / 100
        );

        // Before Liquidation
        (, uint256 onPoolBorrowerBefore) = morpho.borrowBalanceInOf(
            borrowedAsset,
            address(borrower1)
        );

        // Liquidate
        uint256 toRepay = ((borrowedAmount / 2) * _randomModulo) / 255;
        assumeLiquidateAmountIsCorrect(toRepay);

        User liquidator = borrower3;
        liquidator.approve(borrowedUnderlying, address(morpho), toRepay);

        liquidator.liquidate(borrowedAsset, suppliedAsset, address(borrower1), toRepay);

        // After Liquidation
        (, uint256 onPoolBorrowerAfter) = morpho.borrowBalanceInOf(
            borrowedAsset,
            address(borrower1)
        );

        assertLt(onPoolBorrowerBefore, onPoolBorrowerAfter);
    }
}
