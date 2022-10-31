// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetupFuzzing.sol";
import {Attacker} from "../../compound/helpers/Attacker.sol";

contract TestWithdrawFuzzing is TestSetupFuzzing {
    function testWithdraw1Fuzzed(
        uint128 _suppliedAmount,
        uint8 _borrowedAsset,
        uint8 _suppliedAsset
    ) public {
        (address suppliedAsset, address suppliedUnderlying) = getSupplyAsset(_suppliedAsset);
        (address borrowedAsset, ) = getAsset(_borrowedAsset);

        uint256 suppliedAmount = _suppliedAmount;
        assumeSupplyAmountIsCorrect(suppliedUnderlying, suppliedAmount);
        hevm.assume(suppliedAmount > 10**ERC20(suppliedUnderlying).decimals());

        borrower1.approve(suppliedUnderlying, suppliedAmount);
        borrower1.supply(suppliedAsset, suppliedAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            borrowedAsset
        );
        borrowable = (borrowable * 95) / 100;
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

    function testWithdrawMultipleAssetsFuzzed(
        uint8 _proportionBorrowed,
        uint8 _suppliedAsset1,
        uint8 _suppliedAsset2,
        uint128 _amount1,
        uint128 _amount2
    ) public {
        (address asset1, address underlying1) = getAsset(_suppliedAsset1);
        (address asset2, address underlying2) = getAsset(_suppliedAsset2);

        hevm.assume(_amount1 >= 1e14 && _amount1 < ERC20(underlying1).balanceOf(address(asset1)));
        hevm.assume(_amount2 >= 1e14 && _amount2 < ERC20(underlying2).balanceOf(address(asset2)));
        hevm.assume(_proportionBorrowed > 0);

        supplier1.approve(underlying1, _amount1);
        supplier1.supply(asset1, _amount1);
        supplier1.approve(underlying2, _amount2);
        supplier1.supply(asset2, _amount2);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, 10_000_000 * 1e18);

        (, uint256 borrowable1) = lens.getUserMaxCapacitiesForAsset(address(borrower1), asset1);
        (, uint256 borrowable2) = lens.getUserMaxCapacitiesForAsset(address(borrower1), asset2);

        // Amounts available in the cTokens
        uint256 compBalance1 = ERC20(underlying1).balanceOf(asset1);
        uint256 compBalance2 = ERC20(underlying2).balanceOf(asset2);

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
