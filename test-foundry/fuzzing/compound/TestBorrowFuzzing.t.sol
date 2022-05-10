// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";

contract TestBorrowFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    function testBorrow1(
        uint128 _supplied,
        uint128 _borrowed,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 supplied = _supplied;
        uint256 borrowed = _borrowed;

        assumeSupplyAmountIsCorrect(suppliedUnderlying, supplied);

        borrower1.approve(suppliedUnderlying, supplied);
        borrower1.supply(suppliedAsset, supplied);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        hevm.assume(borrowed > borrowable + 1); // +1 to cover for rounding error

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.borrow(borrowedAsset, borrowed);
    }

    function testBorrow2(
        uint128 _amountSupplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _randomModulo
    ) public {
        hevm.assume(_randomModulo != 0);
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;

        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountSupplied);

        borrower1.approve(suppliedUnderlying, amountSupplied);
        borrower1.supply(suppliedAsset, amountSupplied);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );
        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);
    }

    function testBorrow3(
        uint128 _amountSupplied,
        uint128 _amountCollateral,
        uint8 _matchedAsset,
        uint8 _collateralAsset,
        uint8 _randomModulo
    ) public {
        hevm.assume(_randomModulo != 0);
        (address matchedAsset, address matchedUnderlying) = getAsset(_matchedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;
        uint256 amountCollateral = _amountCollateral;

        assumeSupplyAmountIsCorrect(collateralUnderlying, _amountCollateral);
        assumeSupplyAmountIsCorrect(matchedUnderlying, amountSupplied);

        supplier1.approve(matchedUnderlying, amountSupplied);
        supplier1.supply(matchedAsset, amountSupplied);

        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            matchedAsset
        );

        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        assumeBorrowAmountIsCorrect(matchedAsset, borrowedAmount);
        borrower1.borrow(matchedAsset, borrowedAmount);
    }

    // There is no difference between Borrow3 & 4 because amount proportion aren't pre-determined.

    function testBorrow5(
        uint128 _amountSupplied,
        uint128 _amountCollateral,
        uint8 _matchedAsset,
        uint8 _collateralAsset,
        uint8 _randomModulo
    ) public {
        hevm.assume(_randomModulo != 0);
        (address matchedAsset, address matchedUnderlying) = getAsset(_matchedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;
        uint256 amountCollateral = _amountCollateral;

        assumeSupplyAmountIsCorrect(collateralUnderlying, amountCollateral);

        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            matchedAsset
        );
        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        assumeBorrowAmountIsCorrect(matchedAsset, borrowedAmount);

        uint256 NMAX = ((20 * uint256(_randomModulo)) / 255) + 1;
        createSigners(NMAX);

        uint256 amountPerSupplier = (amountSupplied / NMAX) + 1;
        assumeSupplyAmountIsCorrect(matchedUnderlying, amountPerSupplier);

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(matchedUnderlying, amountPerSupplier);
            suppliers[i].supply(matchedAsset, amountPerSupplier);
        }

        borrower1.borrow(matchedAsset, borrowedAmount);
    }

    function testBorrowMultipleAssets(
        uint128 _amountCollateral,
        uint8 _firstAsset,
        uint8 _secondAsset,
        uint8 _collateralAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 != 0);
        hevm.assume(_random2 != 0);

        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);
        (address firstAsset, ) = getAsset(_firstAsset);
        (address secondAsset, ) = getAsset(_secondAsset);

        uint256 amountCollateral = _amountCollateral;

        assumeSupplyAmountIsCorrect(collateralUnderlying, amountCollateral);

        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), firstAsset);
        uint256 borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(firstAsset, borrowedAmount);
        borrower1.borrow(firstAsset, borrowedAmount);

        (, borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), secondAsset);
        borrowedAmount = (borrowable * _random2) / 255;
        assumeBorrowAmountIsCorrect(secondAsset, borrowedAmount);
        borrower1.borrow(secondAsset, borrowedAmount);
    }
}
