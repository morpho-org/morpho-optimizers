// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

contract TestBorrow is TestSetupFuzzing {
    using CompoundMath for uint256;

    function testBorrowShouldFailFuzzed(
        uint256 _supplied,
        uint256 _borrowed,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        hevm.assume(
            _supplied != 0 &&
                _supplied <
                ERC20(suppliedUnderlying).balanceOf(address(supplier1)) /
                    10**(ERC20(suppliedUnderlying).decimals()) &&
                _borrowed != 0 &&
                _borrowed < 1e35
        );

        borrower1.approve(suppliedUnderlying, _supplied);
        borrower1.supply(suppliedAsset, _supplied);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        hevm.assume(_borrowed > borrowable + 1); // +1 to cover for rounding error

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.borrow(borrowedAsset, _borrowed);
    }

    function testBorrowFuzzed(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        // uint256 balanceSuppliedBefore = ERC20(suppliedUnderlying).balanceOf(address(borrower1));
        // uint256 balanceBorrowedBefore = ERC20(borrowedUnderlying).balanceOf(address(borrower1));

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
}
