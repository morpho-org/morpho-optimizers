// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetupFuzzing.sol";

contract TestRepayFuzzing is TestSetupFuzzing {
    // Simple repay on pool.
    function testRepay1Fuzzed(
        uint128 _supplied,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 > 10);
        hevm.assume(_random2 > 10);

        (address suppliedAsset, address suppliedUnderlying) = getSupplyAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 supplied = getSupplyAmount(suppliedUnderlying, _supplied);
        borrower1.approve(suppliedUnderlying, supplied);
        borrower1.supply(suppliedAsset, supplied);

        uint256 borrowable = getBorrowAmount(borrowedAsset, 95);
        uint256 borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(borrowedAsset, borrowedAmount);
        borrower1.borrow(borrowedAsset, borrowedAmount);

        uint256 repaidAmount = (borrowedAmount * _random2) / 255;
        assumeRepayAmountIsCorrect(borrowedUnderlying, repaidAmount);
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
        hevm.assume(_random1 > 10);
        hevm.assume(_random2 > 10);
        hevm.assume(_random3 > 10);

        (address suppliedAsset, address suppliedUnderlying) = getSupplyAsset(_suppliedAsset);
        (address borrowedAsset, address borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 suppliedAmount = getSupplyAmount(suppliedUnderlying, _suppliedAmount);
        borrower1.approve(suppliedUnderlying, suppliedAmount);
        borrower1.supply(suppliedAsset, suppliedAmount);

        // Borrower1 borrows borrowedAmount.
        uint256 borrowable = getBorrowAmount(borrowedAsset, 95);
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
        assumeRepayAmountIsCorrect(borrowedUnderlying, repaidAmount);
        borrower1.approve(borrowedUnderlying, repaidAmount);
        borrower1.repay(borrowedAsset, repaidAmount);
    }
}
