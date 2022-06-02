// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";

contract TestSupplyFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    struct AssetVars {
        address suppliedCToken;
        address suppliedUnderlying;
        address borrowedCToken;
        address borrowedUnderlying;
        address collateralCToken;
        address collateralUnderlying;
    }

    function testSupply1Fuzzed(uint128 _amount, uint8 _asset) public {
        (address asset, address underlying) = getAsset(_asset);
        uint256 amount = _amount;

        assumeSupplyAmountIsCorrect(underlying, amount);
        supplier1.approve(underlying, amount);
        supplier1.supply(asset, amount);

        uint256 supplyPoolIndex = ICToken(asset).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(supplyPoolIndex);

        testEquality(ERC20(asset).balanceOf(address(morpho)), expectedOnPool, "balance of cToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(asset, address(supplier1));

        testEquality(onPool, ICToken(asset).balanceOf(address(morpho)), "on pool");
        testEquality(onPool, expectedOnPool, "on pool");
        assertEq(inP2P, 0, "in P2P");
    }

    function testSupply2Fuzzed(
        uint128 _suppliedAmount,
        uint8 _randomModulo,
        uint8 _suppliedCToken,
        uint8 _borrowedCToken
    ) public {
        hevm.assume(_randomModulo > 0);
        AssetVars memory vars;

        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_suppliedCToken);
        (vars.borrowedCToken, vars.borrowedUnderlying) = getAsset(_borrowedCToken);

        uint256 suppliedAmount = _suppliedAmount;

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, 2 * suppliedAmount);
        // Because there are two supply with suppliedAmount

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedCToken, suppliedAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.borrowedCToken
        );

        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        assumeBorrowAmountIsCorrect(vars.borrowedCToken, borrowedAmount);
        borrower1.borrow(vars.borrowedCToken, borrowedAmount);

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedCToken, suppliedAmount);
    }

    // what is fuzzed is the proportion in P2P on the supply of the second user
    function testSupply3Fuzzed(
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset,
        uint8 _random1
    ) public {
        AssetVars memory vars;
        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_supplyAsset);
        (vars.collateralCToken, vars.collateralUnderlying) = getAsset(_collateralAsset);

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);

        uint256 collateralAmountToSupply = ERC20(vars.collateralUnderlying).balanceOf(
            address(borrower1)
        );

        borrower1.approve(vars.collateralUnderlying, collateralAmountToSupply);
        borrower1.supply(vars.collateralCToken, collateralAmountToSupply);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.suppliedCToken
        );
        uint256 borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(vars.suppliedCToken, borrowedAmount);

        borrower1.borrow(vars.suppliedCToken, borrowedAmount);

        supplier1.approve(vars.suppliedUnderlying, _suppliedAmount);
        supplier1.supply(vars.suppliedCToken, _suppliedAmount);
    }

    // what is fuzzed is the amount supplied
    function testSupply4Fuzzed(
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset,
        uint8 _random1
    ) public {
        AssetVars memory vars;
        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_supplyAsset);
        (vars.collateralCToken, vars.collateralUnderlying) = getAsset(_collateralAsset);
        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        uint256 amountPerBorrower = _suppliedAmount / NMAX;

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);
        assumeBorrowAmountIsCorrect(vars.suppliedCToken, NMAX * amountPerBorrower);

        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );
        createSigners(NMAX);

        uint256 collateralAmount = ERC20(vars.collateralUnderlying).balanceOf(address(borrower1));
        borrower1.approve(vars.collateralUnderlying, collateralAmount);
        borrower1.supply(vars.collateralCToken, collateralAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.suppliedCToken
        );

        hevm.assume(amountPerBorrower < borrowable);
        borrower1.borrow(vars.suppliedCToken, amountPerBorrower);
        for (uint256 i = 1; i < NMAX - 1; i++) {
            borrowers[i + 1].approve(vars.collateralUnderlying, collateralAmount);
            borrowers[i + 1].supply(vars.collateralCToken, collateralAmount);
            borrowers[i + 1].borrow(vars.suppliedCToken, amountPerBorrower);
        }

        supplier1.approve(vars.suppliedUnderlying, _suppliedAmount);
        supplier1.supply(vars.suppliedCToken, _suppliedAmount);
    }

    // what is fuzzed is the amount supplied
    function testSupply5Fuzzed(
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset,
        uint8 _random1
    ) public {
        AssetVars memory vars;
        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_supplyAsset);
        (vars.collateralCToken, vars.collateralUnderlying) = getAsset(_collateralAsset);
        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        uint256 amountPerBorrower = _suppliedAmount / (2 * NMAX);

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);
        assumeBorrowAmountIsCorrect(vars.suppliedCToken, NMAX * amountPerBorrower);

        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 collateralAmount = ERC20(vars.collateralUnderlying).balanceOf(address(borrower1));

        {
            borrower1.approve(vars.collateralUnderlying, collateralAmount);
            borrower1.supply(vars.collateralCToken, collateralAmount);
            (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
                address(borrower1),
                vars.suppliedCToken
            );
            hevm.assume(borrowable >= amountPerBorrower);
            borrower1.borrow(vars.suppliedCToken, amountPerBorrower);
        }
        createSigners(NMAX);

        for (uint256 i = 0; i < NMAX - 1; i++) {
            borrowers[i + 1].approve(vars.collateralUnderlying, collateralAmount);
            borrowers[i + 1].supply(vars.collateralCToken, collateralAmount);
            borrowers[i + 1].borrow(vars.suppliedCToken, amountPerBorrower);
        }

        {
            uint256 actuallySupplied = (_suppliedAmount / NMAX) * NMAX;
            supplier1.approve(vars.suppliedUnderlying, actuallySupplied);
            supplier1.supply(vars.suppliedCToken, actuallySupplied);
        }
    }
}
