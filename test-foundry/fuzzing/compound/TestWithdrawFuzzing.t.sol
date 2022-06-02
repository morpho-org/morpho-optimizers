// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";
import {Attacker} from "../../compound/helpers/Attacker.sol";

contract TestWithdrawFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    function testWithdraw1Fuzzed(
        uint128 _suppliedAmount,
        uint8 _borrowedAsset,
        uint8 _suppliedAsset
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 suppliedAmount = _suppliedAmount;
        assumeSupplyAmountIsCorrect(suppliedUnderlying, suppliedAmount);
        hevm.assume(suppliedAmount > 10**ERC20(suppliedUnderlying).decimals());
        // You need this to make sure that even with compound's approximation, you'll have an amount to withdraw

        borrower1.approve(suppliedUnderlying, suppliedAmount);
        borrower1.supply(suppliedAsset, suppliedAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );
        assumeBorrowAmountIsCorrect(borrowedAsset, borrowable);
        borrower1.borrow(borrowedAsset, borrowable);

        assumeWithdrawAmountIsCorrect(suppliedAsset, suppliedAmount);
        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedWithdraw()"));
        borrower1.withdraw(suppliedAsset, suppliedAmount);
    }

    function testWithdraw2Fuzzed(
        uint128 _suppliedAmount,
        uint8 _suppliedAsset,
        uint8 _random1
    ) public {
        hevm.assume(_random1 != 0);
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);

        uint256 suppliedAmount = _suppliedAmount;
        assumeSupplyAmountIsCorrect(suppliedUnderlying, suppliedAmount);
        hevm.assume(suppliedAmount > 10**ERC20(suppliedUnderlying).decimals());
        // You need this to make sure that even with compound's approximation, you'll have an amount to withdraw

        supplier1.approve(suppliedUnderlying, suppliedAmount);
        supplier1.supply(suppliedAsset, suppliedAmount);

        uint256 withdrawnAmount = (suppliedAmount * _random1) / 255;
        assumeWithdrawAmountIsCorrect(suppliedAsset, withdrawnAmount);
        supplier1.withdraw(suppliedAsset, withdrawnAmount);
    }

    function testWithdrawAllFuzzed(uint128 _suppliedAmount, uint8 _suppliedAsset) public {
        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);

        uint256 suppliedAmount = _suppliedAmount;
        assumeSupplyAmountIsCorrect(suppliedUnderlying, suppliedAmount);
        hevm.assume(suppliedAmount > 10**ERC20(suppliedUnderlying).decimals());
        // You need this to make sure that even with compound's approximation, you'll have an amount to withdraw

        supplier1.approve(suppliedUnderlying, suppliedAmount);
        supplier1.supply(suppliedAsset, suppliedAmount);
        supplier1.withdraw(suppliedAsset, type(uint256).max);
    }

    function testWithdraw3_1Fuzzed(
        uint128 _amountSupplied,
        uint8 _collateralAsset,
        uint8 _suppliedAsset,
        uint8 _random1
    ) public {
        hevm.assume(_random1 != 0);

        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;

        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountSupplied);
        hevm.assume(amountSupplied > 10**ERC20(suppliedUnderlying).decimals());
        // You need this to make sure that even with compound's approximation, you'll have an amount to withdraw

        // Borrower1 & supplier1 are matched for amountSupplied.
        uint256 collateralToSupply = ERC20(collateralUnderlying).balanceOf(address(borrower1));

        borrower1.approve(collateralUnderlying, collateralToSupply);
        borrower1.supply(collateralAsset, collateralToSupply);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            suppliedAsset
        );
        hevm.assume(borrowable > amountSupplied);
        assumeBorrowAmountIsCorrect(suppliedAsset, amountSupplied);
        borrower1.borrow(suppliedAsset, amountSupplied);

        supplier1.approve(suppliedUnderlying, amountSupplied);
        supplier1.supply(suppliedAsset, amountSupplied);

        // Supplier1 withdraws a random amount.
        uint256 withdrawnAmount = (amountSupplied * _random1) / 255;
        assumeWithdrawAmountIsCorrect(suppliedAsset, withdrawnAmount);
        supplier1.withdraw(suppliedAsset, withdrawnAmount);
    }

    function testWithdraw3_2Fuzzed(
        uint128 _amountSupplied,
        uint8 _collateralAsset,
        uint8 _suppliedAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 != 0);
        hevm.assume(_random2 != 0);

        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;

        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountSupplied);
        hevm.assume(amountSupplied > 10**ERC20(suppliedUnderlying).decimals());
        // You need this to make sure that even with compound's a3_2pproximation, you'll have an amount to withdraw
        hevm.assume(amountSupplied < ICToken(suppliedAsset).getCash());
        // In order to make sure that the Delta from the withdraw won't take more than what's available on the market

        // Borrower1 & supplier1 are matched for suppliedAmount.
        supplier1.approve(suppliedUnderlying, amountSupplied);
        supplier1.supply(suppliedAsset, amountSupplied);

        uint256 collateralToSupply = ERC20(collateralUnderlying).balanceOf(address(borrower1));
        borrower1.approve(collateralUnderlying, collateralToSupply);
        borrower1.supply(collateralAsset, collateralToSupply);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            suppliedAsset
        );
        hevm.assume(borrowable > amountSupplied);
        assumeBorrowAmountIsCorrect(suppliedAsset, amountSupplied);
        borrower1.borrow(suppliedAsset, amountSupplied);

        // NMAX suppliers have up to suppliedAmount waiting on pool
        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        createSigners(NMAX);

        uint256 amountPerSupplier = amountSupplied / NMAX;
        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountPerSupplier);

        for (uint256 i = 1; i < NMAX; i++) {
            suppliers[i].approve(suppliedUnderlying, amountPerSupplier);
            suppliers[i].supply(suppliedAsset, amountPerSupplier);
        }

        uint256 withdrawnAmount = (amountSupplied * _random2) / 255;
        assumeWithdrawAmountIsCorrect(suppliedAsset, withdrawnAmount);
        supplier1.withdraw(suppliedAsset, type(uint256).max);
    }

    function testWithdraw3_4Fuzzed(
        uint128 _amountSupplied,
        uint8 _collateralAsset,
        uint8 _suppliedAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 != 0);
        hevm.assume(_random2 != 0);

        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;

        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountSupplied);
        hevm.assume(amountSupplied > 10**ERC20(suppliedUnderlying).decimals());
        // You need this to make sure that even with compound's approximation, you'll have an amount to withdraw
        hevm.assume(amountSupplied < ICToken(suppliedAsset).getCash());
        // In order to make sure that the Delta from the withdraw won't take more than what's available on the market

        // Borrower1 & supplier1 are matched for suppliedAmount.
        supplier1.approve(suppliedUnderlying, amountSupplied);
        supplier1.supply(suppliedAsset, amountSupplied);

        uint256 collateralToSupply = ERC20(collateralUnderlying).balanceOf(address(borrower1));
        borrower1.approve(collateralUnderlying, collateralToSupply);
        borrower1.supply(collateralAsset, collateralToSupply);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            suppliedAsset
        );
        hevm.assume(borrowable > amountSupplied);
        assumeBorrowAmountIsCorrect(suppliedAsset, amountSupplied);
        borrower1.borrow(suppliedAsset, amountSupplied);

        // NMAX suppliers have up to suppliedAmount waiting on pool
        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        createSigners(NMAX);

        uint256 amountPerSupplier = amountSupplied / (2 * NMAX);
        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountPerSupplier);

        for (uint256 i = 1; i < NMAX; i++) {
            suppliers[i].approve(suppliedUnderlying, amountPerSupplier);
            suppliers[i].supply(suppliedAsset, amountPerSupplier);
        }

        uint256 withdrawnAmount = (amountSupplied * _random2) / 255;
        assumeWithdrawAmountIsCorrect(suppliedAsset, withdrawnAmount);
        supplier1.withdraw(suppliedAsset, type(uint256).max);
    }

    function testDeltaWithdrawFuzzed(
        uint128 _amountSupplied,
        uint8 _collateralAsset,
        uint8 _suppliedAsset,
        uint8 _random1,
        uint8 _random2
    ) public {
        hevm.assume(_random1 != 0);
        hevm.assume(_random2 != 0);

        (address suppliedAsset, address suppliedUnderlying) = getAsset(_suppliedAsset);
        (address collateralAsset, address collateralUnderlying) = getAsset(_collateralAsset);

        uint256 amountSupplied = _amountSupplied;

        // 2e6 allows only 10 unmatch borrowers.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 2e6, 2e6);

        // supplier1 and 20 borrowers are matched for amountSupplied.
        assumeSupplyAmountIsCorrect(suppliedUnderlying, amountSupplied);
        hevm.assume(amountSupplied < ICToken(suppliedAsset).getCash());
        // In order to make sure that the Delta from the withdraw won't take more than what's available on the market

        hevm.assume(amountSupplied > 10**ERC20(suppliedUnderlying).decimals());
        // You need this to make sure that even with compound's approximation, you'll have an amount to withdraw

        supplier1.approve(suppliedUnderlying, amountSupplied);
        supplier1.supply(suppliedAsset, amountSupplied);

        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        createSigners(NMAX);

        uint256 collateralToSupply = ERC20(collateralUnderlying).balanceOf(address(borrower1));
        borrower1.approve(collateralUnderlying, collateralToSupply);
        borrower1.supply(collateralAsset, collateralToSupply);

        // Use borrower1 first to check that those borrow are fine.
        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            suppliedAsset
        );
        uint256 amountPerBorrower = amountSupplied / NMAX;
        hevm.assume(borrowable >= amountPerBorrower);

        assumeBorrowAmountIsCorrect(suppliedAsset, NMAX * amountPerBorrower);
        borrower1.borrow(suppliedAsset, amountPerBorrower);

        for (uint256 i = 1; i < NMAX; i++) {
            borrowers[i].approve(collateralUnderlying, collateralToSupply);
            borrowers[i].supply(collateralAsset, collateralToSupply);
            borrowers[i].borrow(suppliedAsset, amountPerBorrower);
        }

        {
            // Supplier withdraws max.
            // Should create a delta on borrowers side.
            supplier1.withdraw(suppliedAsset, type(uint256).max);

            // supplier should be able to deposit to help remove delta
            supplier2.approve(suppliedUnderlying, amountSupplied);
            supplier2.supply(suppliedAsset, amountSupplied);
        }

        moveOneBlockForwardBorrowRepay();

        // Borrow delta reduction with borrowers repaying
        for (uint256 i = NMAX / 2; i < NMAX; i++) {
            borrowers[i].approve(suppliedUnderlying, amountPerBorrower);
            borrowers[i].repay(suppliedAsset, amountPerBorrower);
        }
    }

    function testWithdrawMultipleAssetsFuzzed(
        uint8 _proportionBorrowed,
        uint8 _suppliedAsset1,
        uint8 _suppliedAsset2,
        uint128 _amount1,
        uint128 _amount2
    ) public {
        (address asset1, address underlying1) = getAsset(_suppliedAsset1);
        (address asset2, address underlying2) = getAsset(_suppliedAsset2);

        hevm.assume(
            _amount1 >= 1e14 && _amount1 < ERC20(underlying1).balanceOf(address(asset1)) // Less than the available liquidity of CTokens, but more than would be rounded to zero
        );
        hevm.assume(_amount2 >= 1e14 && _amount2 < ERC20(underlying2).balanceOf(address(asset2)));
        hevm.assume(_proportionBorrowed > 0);

        supplier1.approve(underlying1, _amount1);
        supplier1.supply(asset1, _amount1);
        supplier1.approve(underlying2, _amount2);
        supplier1.supply(asset2, _amount2);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, 10_000_000 * 1e18);

        (, uint256 borrowable1) = lens.getUserMaxCapacitiesForAsset(address(borrower1), asset1);
        (, uint256 borrowable2) = lens.getUserMaxCapacitiesForAsset(address(borrower1), asset2);

        // Amounts available in the cTokens
        uint256 compBalance1 = asset1 == cEth
            ? asset1.balance
            : ERC20(underlying1).balanceOf(asset1);
        uint256 compBalance2 = asset2 == cEth
            ? asset2.balance
            : ERC20(underlying2).balanceOf(asset2);

        borrowable1 = borrowable1 > compBalance1 ? compBalance1 : borrowable1;
        borrowable2 = borrowable2 > compBalance2 ? compBalance2 : borrowable2;

        uint256 toBorrow1 = (_amount1 * _proportionBorrowed) / type(uint8).max;
        toBorrow1 = toBorrow1 > borrowable1 / 2 ? borrowable1 / 2 : toBorrow1;
        uint256 toBorrow2 = (_amount2 * _proportionBorrowed) / type(uint8).max;
        toBorrow2 = toBorrow2 > borrowable2 / 2 ? borrowable2 / 2 : toBorrow2;

        borrower1.borrow(asset1, toBorrow1);
        borrower1.borrow(asset2, toBorrow2);

        supplier1.withdraw(asset1, _amount1);
        supplier1.withdraw(asset2, _amount2);
    }
}
