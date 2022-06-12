// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";

contract TestBorrowFuzzing is TestSetupFuzzing {
    function testBorrow1(
        uint128 _supplied,
        uint128 _borrowed,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getSupplyAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 supplied = _supplied;
        uint256 borrowed = _borrowed;

        supplied = getSupplyAmount(suppliedUnderlying, supplied);

        borrower1.approve(suppliedUnderlying, supplied);
        borrower1.supply(suppliedAsset, supplied);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        hevm.assume(borrowed > borrowable + 1); // +1 to cover for rounding error

        hevm.expectRevert(EntryPositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(borrowedAsset, borrowed);
    }

    function testBorrow2(
        uint128 _amountSupplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _random1
    ) public {
        hevm.assume(_random1 != 0);
        (address suppliedAsset, address suppliedUnderlying) = getSupplyAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;

        amountSupplied = getSupplyAmount(suppliedUnderlying, amountSupplied);

        borrower1.approve(suppliedUnderlying, amountSupplied);
        borrower1.supply(suppliedAsset, amountSupplied);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        uint256 borrowedAmount = (borrowable * _random1) / 255;
        hevm.assume(borrowedAmount + 5 < borrowable); // +5 to cover for rounding error

        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);
    }

    function testBorrow3(
        uint128 _amountSupplied,
        uint128 _amountCollateral,
        uint8 _matchedAsset,
        uint8 _collateralAsset,
        uint8 _random1
    ) public {
        hevm.assume(_random1 != 0);
        (address matchedAsset, address matchedUnderlying) = getSupplyAsset(_matchedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;
        uint256 amountCollateral = _amountCollateral;

        amountCollateral = getSupplyAmount(collateralUnderlying, _amountCollateral);
        amountSupplied = getSupplyAmount(matchedUnderlying, amountSupplied);

        supplier1.approve(matchedUnderlying, amountSupplied);
        supplier1.supply(matchedAsset, amountSupplied);

        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            matchedAsset
        );

        uint256 borrowedAmount = (borrowable * _random1) / 255;
        hevm.assume(borrowedAmount + 5 < borrowable); // +5 to cover for rounding error

        assumeBorrowAmountIsCorrect(matchedAsset, borrowedAmount);
        borrower1.borrow(matchedAsset, borrowedAmount);
    }

    // There is no difference between Borrow3 & 4 because amount proportion aren't pre-determined.

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

        (address collateralAsset, address collateralUnderlying) = getSupplyAsset(_collateralAsset);
        (address firstAsset, ) = getAsset(_firstAsset);
        (address secondAsset, ) = getAsset(_secondAsset);

        uint256 amountCollateral = _amountCollateral;

        amountCollateral = getSupplyAmount(collateralUnderlying, amountCollateral);

        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), firstAsset);
        uint256 borrowedAmount = (borrowable * _random1) / 255;
        hevm.assume(borrowedAmount + 5 < borrowable); // +5 to cover for rounding error

        assumeBorrowAmountIsCorrect(firstAsset, borrowedAmount);
        borrower1.borrow(firstAsset, borrowedAmount);

        (, borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), secondAsset);
        borrowedAmount = (borrowable * _random2) / 255;
        hevm.assume(borrowedAmount + 5 < borrowable); // +5 to cover for rounding error
        assumeBorrowAmountIsCorrect(secondAsset, borrowedAmount);
        borrower1.borrow(secondAsset, borrowedAmount);
    }
}
