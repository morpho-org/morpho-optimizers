// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

contract TestBorrow is TestSetupFuzzing {
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

        hevm.assume(
            supplied != 0 &&
                supplied <
                ERC20(suppliedUnderlying).balanceOf(address(supplier1)) /
                    10**(ERC20(suppliedUnderlying).decimals()) &&
                borrowed != 0 &&
                borrowed < 1e35
        );

        borrower1.approve(suppliedUnderlying, supplied);
        borrower1.supply(suppliedAsset, supplied);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        hevm.assume(borrowed > borrowable + 1); // +1 to cover for rounding error

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.borrow(borrowedAsset, borrowed);
    }

    function testBorrow2(
        uint128 _amountSupplied,
        uint128 _amountBorrowed,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;
        uint256 amountBorrowed = _amountBorrowed;

        hevm.assume(
            amountSupplied != 0 &&
                amountSupplied <
                ERC20(suppliedUnderlying).balanceOf(address(borrower1)) /
                    10**(ERC20(suppliedUnderlying).decimals()) &&
                amountBorrowed != 0
        );

        borrower1.approve(suppliedUnderlying, amountSupplied);
        borrower1.supply(suppliedAsset, amountSupplied);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        hevm.assume(amountBorrowed <= borrowable);
        borrower1.borrow(borrowedAsset, amountBorrowed);
    }

    function testBorrow3(
        uint128 _amountSupplied,
        uint128 _amountCollateral,
        uint8 _matchedAsset,
        uint8 _collateralAsset,
        uint8 _randomModulo
    ) public {
        (address matchedAsset, address matchedUnderlying) = getAsset(_matchedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;
        uint256 amountCollateral = _amountCollateral;

        hevm.assume(
            amountSupplied != 0 &&
                amountSupplied <
                ERC20(matchedUnderlying).balanceOf(address(borrower1)) /
                    10**(ERC20(matchedUnderlying).decimals()) &&
                _randomModulo != 0 &&
                amountCollateral != 0 &&
                amountCollateral <
                ERC20(collateralUnderlying).balanceOf(address(borrower1)) /
                    10**(ERC20(collateralUnderlying).decimals())
        );

        supplier1.approve(matchedUnderlying, amountSupplied);
        supplier1.supply(matchedAsset, amountSupplied);

        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            matchedAsset
        );

        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        hevm.assume(borrowedAmount != 0);
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
        (address matchedAsset, address matchedUnderlying) = getAsset(_matchedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;
        uint256 amountCollateral = _amountCollateral;

        hevm.assume(
            amountSupplied != 0 &&
                amountSupplied <
                ERC20(matchedUnderlying).balanceOf(address(borrower1)) /
                    10**(ERC20(matchedUnderlying).decimals()) &&
                amountCollateral != 0 &&
                amountCollateral <
                ERC20(collateralUnderlying).balanceOf(address(borrower1)) /
                    10**(ERC20(collateralUnderlying).decimals())
        );

        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            matchedAsset
        );
        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        hevm.assume(borrowedAmount != 0);

        uint256 NMAX = ((20 * uint256(_randomModulo)) / 255) + 1;
        createSigners(NMAX);

        uint256 amountPerSupplier = (amountSupplied / NMAX) + 1;

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
        uint8 _firstRandom,
        uint8 _secondRandom
    ) public {
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);
        (address firstAsset, ) = getAsset(_firstAsset);
        (address secondAsset, ) = getAsset(_secondAsset);

        uint256 amountCollateral = _amountCollateral;

        hevm.assume(
            _amountCollateral != 0 &&
                _amountCollateral <
                ERC20(collateralUnderlying).balanceOf(address(borrower1)) /
                    10**(ERC20(collateralUnderlying).decimals())
        );
        borrower1.approve(collateralUnderlying, amountCollateral);
        borrower1.supply(collateralAsset, amountCollateral);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            firstAsset
        );
        uint256 borrowedAmount = (borrowable * _firstRandom) / 255;
        hevm.assume(borrowedAmount != 0);
        borrower1.borrow(firstAsset, borrowedAmount);

        (, borrowable) = morpho.getUserMaxCapacitiesForAsset(address(borrower1), secondAsset);
        borrowedAmount = (borrowable * _secondRandom) / 255;
        hevm.assume(borrowedAmount != 0);
        borrower1.borrow(secondAsset, borrowedAmount);
    }
}
