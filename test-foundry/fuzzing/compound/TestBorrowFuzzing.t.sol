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
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _randomModulo
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 amountSupplied = _amountSupplied;

        hevm.assume(
            amountSupplied != 0 &&
                amountSupplied <
                ERC20(suppliedUnderlying).balanceOf(address(borrower1)) /
                    10**(ERC20(suppliedUnderlying).decimals()) &&
                _randomModulo != 0
        );

        supplier1.approve(suppliedUnderlying, amountSupplied);
        supplier1.supply(suppliedAsset, amountSupplied);

        borrower1.approve(suppliedUnderlying, amountSupplied);
        borrower1.supply(suppliedAsset, amountSupplied);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        hevm.assume(borrowedAmount != 0);
        borrower1.borrow(borrowedAsset, borrowedAmount);
    }
}
