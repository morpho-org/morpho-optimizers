// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";

contract TestRepayFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    // Simple repay on pool.
    function testRepay1Fuzzed(
        uint128 _supplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 > 0);
        hevm.assume(_random2 > 0);

        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 supplied = _supplied;
        // To limit number of run where computed amounts are 0.
        hevm.assume(supplied > 10**ERC20(suppliedUnderlying).decimals());

        assumeSupplyAmountIsCorrect(suppliedUnderlying, supplied);

        borrower1.approve(suppliedUnderlying, supplied);
        borrower1.supply(suppliedAsset, supplied);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        uint256 borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);

        uint256 repaidAmount = (borrowedAmount * _random2) / 255;
        assumeRepayAmountIsCorrect(repaidAmount);
        borrower1.approve(borrowedUnderlying, repaidAmount);
        borrower1.repay(borrowedAsset, repaidAmount);
    }

    // Partially matched with one borrower waiting.
    function testRepay2Fuzzed(
        uint128 _supplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _random1,
        uint8 _random2,
        uint8 _random3
    ) public {
        hevm.assume(_random1 > 0);
        hevm.assume(_random2 > 0);
        hevm.assume(_random3 > 0);

        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 supplied = _supplied;
        // To limit number of run where computed amounts are 0.
        hevm.assume(supplied > 10**ERC20(suppliedUnderlying).decimals());

        assumeSupplyAmountIsCorrect(suppliedUnderlying, supplied);

        borrower1.approve(suppliedUnderlying, supplied);
        borrower1.supply(suppliedAsset, supplied);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        // Borrower1 borrow borrowedAmount.
        uint256 borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);

        // He is matched up to matched amount with supplier1.
        uint256 matchedAmount = (borrowedAmount * _random2) / 255;
        hevm.assume(matchedAmount != 0);
        supplier1.approve(borrowedUnderlying, matchedAmount);
        supplier1.supply(borrowedAsset, matchedAmount);

        // Borrower2 has his debt waiting on pool.
        borrower2.approve(suppliedUnderlying, supplied);
        borrower2.supply(suppliedAsset, supplied);
        borrower2.borrow(borrowedAsset, borrowedAmount);

        // Borrower1 repays a random amount.
        uint256 repaidAmount = (borrowedAmount * _random3) / 255;
        assumeRepayAmountIsCorrect(repaidAmount);
        borrower1.approve(borrowedUnderlying, repaidAmount);
        borrower1.repay(borrowedAsset, repaidAmount);
    }

    // Matched, with random number of borrower await on pool to replace.
    function testRepay3Fuzzed(
        uint128 _suppliedAmount,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _random1,
        uint8 _random2,
        uint8 _random3
    ) public {
        hevm.assume(_random1 > 0);
        hevm.assume(_random2 > 0);
        hevm.assume(_random3 > 0);

        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 suppliedAmount = _suppliedAmount;
        // To limit number of run where computed amounts are 0.
        hevm.assume(suppliedAmount > 10**ERC20(suppliedUnderlying).decimals());

        assumeSupplyAmountIsCorrect(suppliedUnderlying, suppliedAmount);

        borrower1.approve(suppliedUnderlying, suppliedAmount);
        borrower1.supply(suppliedAsset, suppliedAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );

        // Borrower1 borrows borrowedAmount.
        uint256 borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);

        // He is matched with supplier1.
        supplier1.approve(borrowedUnderlying, borrowedAmount);
        supplier1.supply(borrowedAsset, borrowedAmount);

        // There is a random number of waiting borrower on pool.
        uint256 nbOfWaitingBorrowers = ((20 * uint256(_random2)) / 255) + 1;
        createSigners(nbOfWaitingBorrowers);
        uint256 amountPerBorrower = borrowedAmount / nbOfWaitingBorrowers;
        assumeBorrowAmountIsCorrect(borrowedAsset, amountPerBorrower);
        for (uint256 i = 2; i < nbOfWaitingBorrowers; i++) {
            borrowers[i].approve(suppliedUnderlying, suppliedAmount);
            borrowers[i].supply(suppliedAsset, suppliedAmount);
            borrowers[i].borrow(borrowedAsset, amountPerBorrower);
        }

        // Borrower1 repays a random amount.
        uint256 repaidAmount = (borrowedAmount * _random3) / 255;
        assumeRepayAmountIsCorrect(repaidAmount);
        borrower1.approve(borrowedUnderlying, repaidAmount);
        borrower1.repay(borrowedAsset, repaidAmount);
    }

    function testRepay4Fuzzed(
        uint128 _borrowAmount,
        uint8 _borrowedAsset,
        uint8 _collateralAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 > 0);
        hevm.assume(_random2 > 0);

        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 collateralToSupply = ERC20(collateralUnderlying).balanceOf(address(borrower1));

        borrower1.approve(collateralUnderlying, collateralToSupply);
        borrower1.supply(collateralAsset, collateralToSupply);

        uint256 borrowAmount = _borrowAmount;
        assumeBorrowAmountIsCorrect(borrowedAsset, borrowAmount);
        borrower1.borrow(borrowedAsset, borrowAmount);

        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        uint256 amountPerUser = borrowAmount / (2 * NMAX);

        assumeSupplyAmountIsCorrect(borrowedUnderlying, amountPerUser);

        createSigners(2 * NMAX);

        for (uint256 i; i < 2 * NMAX; i++) {
            suppliers[i].approve(borrowedUnderlying, amountPerUser);
            suppliers[i].supply(borrowedAsset, amountPerUser);
        }
        for (uint256 j = 1; j <= NMAX; j++) {
            borrowers[j].approve(collateralUnderlying, collateralToSupply);
            borrowers[j].supply(collateralCToken, collateralToSupply);
            borrowers[j].borrow(borrowedCToken, matchersAmountToSupply);
        }

        // Borrower1 repays a random amount.
        uint256 repaidAmount = (borrowAmount * _random2) / 255;
        assumeRepayAmountIsCorrect(repaidAmount);
        borrower1.approve(borrowedUnderlying, type(uint256).max);
        borrower1.repay(borrowedAsset, type(uint256).max);
    }
}
