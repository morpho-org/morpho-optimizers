// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetupFuzzing.sol";

contract TestSupplyFuzzing is TestSetupFuzzing {
    struct AssetVars {
        address suppliedAToken;
        address suppliedUnderlying;
        address borrowedAToken;
        address borrowedUnderlying;
        address collateralAToken;
        address collateralUnderlying;
    }

    function testSupply1Fuzzed(uint128 _amount, uint8 _asset) public {
        (address asset, address underlying) = getSupplyAsset(_asset);
        uint256 amount = _amount;

        assumeSupplyAmountIsCorrect(underlying, amount);
        supplier1.approve(underlying, amount);
        supplier1.supply(asset, amount);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(underlying);
        uint256 expectedOnPool = amount.rayDiv(normalizedIncome);

        testEquality(ERC20(asset).balanceOf(address(morpho)), amount, "balance of aToken");

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(asset, address(supplier1));

        testEquality(onPool, expectedOnPool, "on pool");
        assertEq(inP2P, 0, "in P2P");
    }

    function testSupply2Fuzzed(
        uint128 _suppliedAmount,
        uint8 _randomModulo,
        uint8 _suppliedAToken,
        uint8 _borrowedAToken
    ) public {
        hevm.assume(_randomModulo > 0);
        AssetVars memory vars;

        (vars.suppliedAToken, vars.suppliedUnderlying) = getSupplyAsset(_suppliedAToken);
        (vars.borrowedAToken, vars.borrowedUnderlying) = getAsset(_borrowedAToken);

        uint256 suppliedAmount = _suppliedAmount;

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, 2 * suppliedAmount);
        // Because there are two supply with suppliedAmount

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedAToken, suppliedAmount);

        uint256 borrowable = getBorrowAmount(vars.borrowedAToken, 95);
        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;
        assumeBorrowAmountIsCorrect(vars.borrowedAToken, borrowedAmount);
        borrower1.borrow(vars.borrowedAToken, borrowedAmount);

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedAToken, suppliedAmount);
    }

    // what is fuzzed is the proportion in P2P on the supply of the second user
    function testSupply3Fuzzed(
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset,
        uint8 _random1
    ) public {
        AssetVars memory vars;
        (vars.suppliedAToken, vars.suppliedUnderlying) = getSupplyAsset(_supplyAsset);
        (vars.collateralAToken, vars.collateralUnderlying) = getAsset(_collateralAsset);

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);

        uint256 collateralAmountToSupply = ERC20(vars.collateralUnderlying).balanceOf(
            address(borrower1)
        );

        borrower1.approve(vars.collateralUnderlying, collateralAmountToSupply);
        borrower1.supply(vars.collateralAToken, collateralAmountToSupply);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.suppliedAToken
        );
        uint256 borrowedAmount = (borrowable * _random1) / 255;
        assumeBorrowAmountIsCorrect(vars.suppliedAToken, borrowedAmount);

        borrower1.borrow(vars.suppliedAToken, borrowedAmount);

        supplier1.approve(vars.suppliedUnderlying, _suppliedAmount);
        supplier1.supply(vars.suppliedAToken, _suppliedAmount);
    }

    // what is fuzzed is the amount supplied
    function testSupply4Fuzzed(
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset,
        uint8 _random1
    ) public {
        AssetVars memory vars;
        (vars.suppliedAToken, vars.suppliedUnderlying) = getSupplyAsset(_supplyAsset);
        (vars.collateralAToken, vars.collateralUnderlying) = getAsset(_collateralAsset);
        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        uint256 amountPerBorrower = _suppliedAmount / NMAX;

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);
        assumeBorrowAmountIsCorrect(vars.suppliedAToken, NMAX * amountPerBorrower);

        _setDefaultMaxGasForMatching(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );
        createSigners(NMAX);

        uint256 collateralAmount = ERC20(vars.collateralUnderlying).balanceOf(address(borrower1));
        borrower1.approve(vars.collateralUnderlying, collateralAmount);
        borrower1.supply(vars.collateralAToken, collateralAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.suppliedAToken
        );

        hevm.assume(amountPerBorrower < borrowable);
        borrower1.borrow(vars.suppliedAToken, amountPerBorrower);
        for (uint256 i = 1; i < NMAX - 1; i++) {
            borrowers[i + 1].approve(vars.collateralUnderlying, collateralAmount);
            borrowers[i + 1].supply(vars.collateralAToken, collateralAmount);
            borrowers[i + 1].borrow(vars.suppliedAToken, amountPerBorrower);
        }

        supplier1.approve(vars.suppliedUnderlying, _suppliedAmount);
        supplier1.supply(vars.suppliedAToken, _suppliedAmount);
    }

    // what is fuzzed is the amount supplied
    function testSupply5Fuzzed(
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset,
        uint8 _random1
    ) public {
        AssetVars memory vars;
        (vars.suppliedAToken, vars.suppliedUnderlying) = getSupplyAsset(_supplyAsset);
        (vars.collateralAToken, vars.collateralUnderlying) = getAsset(_collateralAsset);
        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        uint256 amountPerBorrower = _suppliedAmount / (2 * NMAX);

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);
        assumeBorrowAmountIsCorrect(vars.suppliedAToken, NMAX * amountPerBorrower);

        _setDefaultMaxGasForMatching(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 collateralAmount = ERC20(vars.collateralUnderlying).balanceOf(address(borrower1));

        {
            borrower1.approve(vars.collateralUnderlying, collateralAmount);
            borrower1.supply(vars.collateralAToken, collateralAmount);
            (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
                address(borrower1),
                vars.suppliedAToken
            );
            hevm.assume(borrowable >= amountPerBorrower);
            borrower1.borrow(vars.suppliedAToken, amountPerBorrower);
        }
        createSigners(NMAX);

        for (uint256 i = 0; i < NMAX - 1; i++) {
            borrowers[i + 1].approve(vars.collateralUnderlying, collateralAmount);
            borrowers[i + 1].supply(vars.collateralAToken, collateralAmount);
            borrowers[i + 1].borrow(vars.suppliedAToken, amountPerBorrower);
        }

        {
            uint256 actuallySupplied = (_suppliedAmount / NMAX) * NMAX;
            supplier1.approve(vars.suppliedUnderlying, actuallySupplied);
            supplier1.supply(vars.suppliedAToken, actuallySupplied);
        }
    }
}
