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

        assertApproxEq(
            ERC20(asset).balanceOf(address(morpho)),
            expectedOnPool,
            5,
            "balance of cToken"
        );

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(asset, address(supplier1));

        assertApproxEq(onPool, ICToken(asset).balanceOf(address(morpho)), 5, "on pool");
        assertApproxEq(onPool, expectedOnPool, 5, "on pool");
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

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, suppliedAmount);

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedCToken, suppliedAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.borrowedCToken
        );
        borrowable = Math.min(borrowable, ICToken(vars.borrowedCToken).getCash());
        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;

        assumeBorrowAmountIsCorrect(vars.borrowedCToken, borrowedAmount);
        borrower1.borrow(vars.borrowedCToken, borrowedAmount);

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedCToken, suppliedAmount);
    }

    // what is fuzzed is the proportion in P2P on the supply of the second user
    function testSupply3Fuzzed(
        uint128 _borrowedAmount,
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset
    ) public {
        AssetVars memory vars;
        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_supplyAsset);
        (vars.collateralCToken, vars.collateralUnderlying) = getAsset(_collateralAsset);

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);
        assumeBorrowAmountIsCorrect(vars.suppliedUnderlying, _borrowedAmount);

        uint256 collateralAmountToSupply = ERC20(vars.collateralUnderlying).balanceOf(
            address(borrower1)
        );

        borrower1.approve(vars.collateralUnderlying, collateralAmountToSupply);
        borrower1.supply(vars.collateralCToken, collateralAmountToSupply);
        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.suppliedCToken
        );
        hevm.assume(
            borrowable > _suppliedAmount &&
                _borrowedAmount <= borrowable &&
                _borrowedAmount <= ICToken(vars.suppliedCToken).getCash() &&
                _borrowedAmount <= comptroller.borrowCaps(vars.suppliedCToken)
        );
        borrower1.borrow(vars.suppliedCToken, _borrowedAmount);
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
        uint256 amountPerBorrower = _suppliedAmount / NMAX;

        assumeSupplyAmountIsCorrect(vars.suppliedUnderlying, _suppliedAmount);
        assumeBorrowAmountIsCorrect(vars.suppliedUnderlying, amountPerBorrower);

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

        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
        createSigners(NMAX);

        for (uint256 i = 0; i < NMAX - 1; i++) {
            borrowers[i + 1].approve(vars.collateralUnderlying, collateralAmount);
            borrowers[i + 1].supply(vars.collateralCToken, collateralAmount);
            borrowers[i + 1].borrow(vars.suppliedCToken, amountPerBorrower);
        }

        {
            uint256 actuallySupplied = amountPerBorrower * NMAX;
            supplier1.approve(vars.suppliedUnderlying, actuallySupplied);
            supplier1.supply(vars.suppliedCToken, actuallySupplied);
        }
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
        uint256 amountPerBorrower = _suppliedAmount / (2 * NMAX);

        assumeSupplyAmountIsCorrect(vars.suppliedCToken, _suppliedAmount);
        assumeBorrowAmountIsCorrect(vars.suppliedCToken, amountPerBorrower);

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

        uint256 NMAX = ((20 * uint256(_random1)) / 255) + 1;
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
