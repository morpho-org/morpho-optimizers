// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";

contract TestLiquidateFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

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
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;

        // Because this is a Liquidation Test, we need to make sure that the supplied amount is enough
        // To obtain a non zero borrow & liquidation amount.
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
        uint8 _random1
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;

        // Because this is a Liquidation Test, we need to make sure that the supplied amount is enough
        // To obtain a non zero borrow & liquidation amount.
        hevm.assume(amountSupplied > 10**ERC20(suppliedUnderlying).decimals());
        hevm.assume(_random1 != 0);
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

        (, uint256 suppliedBorrowerBefore) = morpho.supplyBalanceInOf(
            suppliedAsset,
            address(borrower1)
        );

        // Liquidate
        uint256 toRepay = ((borrowedAmount / 2) * _random1) / 255;
        assumeLiquidateAmountIsCorrect(toRepay);

        User liquidator = borrower3;
        liquidator.approve(borrowedUnderlying, address(morpho), toRepay);

        liquidator.liquidate(borrowedAsset, suppliedAsset, address(borrower1), toRepay);

        // After Liquidation
        (, uint256 onPoolBorrowerAfter) = morpho.borrowBalanceInOf(
            borrowedAsset,
            address(borrower1)
        );
        (, uint256 suppliedBorrowerAfter) = morpho.supplyBalanceInOf(
            suppliedAsset,
            address(borrower1)
        );

        assertLt(onPoolBorrowerBefore, onPoolBorrowerAfter);
        assertLt(suppliedBorrowerBefore, suppliedBorrowerAfter);
    }

    function testLiquidate3Fuzzed(
        uint128 _amountSuppliedForMatch,
        uint128 _amountCollateral,
        uint128 _amountSupplied,
        uint8 _collateralAsset,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 != 0);
        hevm.assume(_random2 != 0);
        addressVars memory vars;

        (vars.suppliedAsset, vars.suppliedUnderlying) = getAsset(_suppliedAsset);
        (vars.borrowedAsset, vars.borrowedUnderlying) = getAsset(_borrowedAsset);
        (vars.collateralAsset, vars.collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;
        uint256 amountSuppliedForMatch = _amountSuppliedForMatch;
        uint256 amountCollateral = _amountCollateral;

        // Because this is a Liquidation Test, we need to make sure that the supplied amount is enough
        // To obtain a non zero borrow & liquidation amount.
        hevm.assume(amountSupplied > 10**ERC20(vars.suppliedUnderlying).decimals());
        hevm.assume(_random1 != 0);
        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, amountSupplied);

        // Borrower1 get his supply & borrow.
        borrower1.approve(vars.suppliedUnderlying, amountSupplied);
        borrower1.supply(vars.suppliedAsset, amountSupplied);
        (, uint256 borrowedAmount) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.borrowedAsset
        );
        assumeBorrowAmountIsCorrect(vars.borrowedAsset, borrowedAmount);
        borrower1.borrow(vars.borrowedAsset, borrowedAmount);

        // Set up Supplier2 to match the borrow asset of Borrower1.
        assumeSupplyAmountIsCorrect(vars.borrowedUnderlying, amountSuppliedForMatch);
        supplier2.approve(vars.borrowedUnderlying, amountSuppliedForMatch);
        supplier2.supply(vars.borrowedAsset, amountSuppliedForMatch);

        // Set up Borrower2 to match the supplied asset of Borrower1.
        assumeSupplyAmountIsCorrect(vars.collateralUnderlying, amountCollateral);
        borrower2.approve(vars.collateralUnderlying, amountCollateral);
        borrower2.supply(vars.collateralAsset, amountCollateral);
        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower2),
            vars.suppliedAsset
        );
        borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(vars.suppliedAsset, borrowedAmount);
        borrower1.borrow(vars.suppliedAsset, borrowedAmount);

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(
            vars.suppliedUnderlying,
            (oracle.getUnderlyingPrice(vars.suppliedAsset) * 94) / 100
        );

        // Before Liquidation
        (, uint256 onPoolBorrowerBefore) = morpho.borrowBalanceInOf(
            vars.borrowedAsset,
            address(borrower1)
        );

        (, uint256 suppliedBorrowerBefore) = morpho.supplyBalanceInOf(
            vars.suppliedAsset,
            address(borrower1)
        );

        // Liquidate
        uint256 toRepay = ((borrowedAmount / 2) * _random2) / 255;
        assumeLiquidateAmountIsCorrect(toRepay);

        User liquidator = borrower3;
        liquidator.approve(vars.borrowedUnderlying, address(morpho), toRepay);

        liquidator.liquidate(vars.borrowedAsset, vars.suppliedAsset, address(borrower1), toRepay);

        // After Liquidation
        (, uint256 onPoolBorrowerAfter) = morpho.borrowBalanceInOf(
            vars.borrowedAsset,
            address(borrower1)
        );

        (, uint256 suppliedBorrowerAfter) = morpho.supplyBalanceInOf(
            vars.suppliedAsset,
            address(borrower1)
        );

        assertLt(onPoolBorrowerBefore, onPoolBorrowerAfter);
        assertLt(suppliedBorrowerBefore, suppliedBorrowerAfter);
    }
}
