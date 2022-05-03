// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

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

        hevm.assume(amount > 0 && amount <= ERC20(underlying).balanceOf(address(supplier1)));

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

    // REVERT
    function testSupply2Fuzzed(
        uint128 _suppliedAmount,
        uint8 _randomModulo,
        uint8 _suppliedCToken,
        uint8 _borrowedCToken
    ) public {
        AssetVars memory vars;

        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_suppliedCToken);
        (vars.borrowedCToken, vars.borrowedUnderlying) = getAsset(_borrowedCToken);

        uint256 suppliedAmount = _suppliedAmount;

        hevm.assume(
            suppliedAmount > 0 &&
                suppliedAmount <=
                2 * ERC20(vars.suppliedUnderlying).balanceOf(address(borrower1)) &&
                _randomModulo > 0
        );

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedCToken, suppliedAmount);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.borrowedCToken
        );
        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;

        hevm.assume(
            borrowedAmount > 0 &&
                borrowedAmount <= ERC20(vars.borrowedUnderlying).balanceOf(address(borrower1))
        );
        borrower1.borrow(vars.borrowedCToken, borrowedAmount);

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedCToken, suppliedAmount);
    }

    // REVERT
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
        hevm.assume(_borrowedAmount > 0 && _suppliedAmount > 0);
        uint256 collateralAmountToSupply = INITIAL_BALANCE *
            (10**ERC20(vars.collateralUnderlying).decimals());
        borrower1.approve(vars.suppliedUnderlying, collateralAmountToSupply);
        console.log(ERC20(dai).allowance(address(borrower1), address(morpho)));

        borrower1.supply(vars.collateralCToken, _suppliedAmount);
        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.suppliedCToken
        );
        hevm.assume(borrowable > _suppliedAmount);

        supplier1.approve(vars.suppliedUnderlying, _suppliedAmount);
        supplier1.supply(vars.suppliedCToken, _suppliedAmount);
    }

    // fail (26154794060679730960, 0, 120) -> event Failure error e info 9 with cYFI active
    // what is fuzzed is the amount supplied & borrowed
    function testSupply4Fuzzed(
        uint128 _suppliedAmount,
        uint8 _collateralAsset,
        uint8 _supplyAsset
    ) public {
        AssetVars memory vars;
        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_supplyAsset);
        (vars.collateralCToken, vars.collateralUnderlying) = getAsset(_collateralAsset);

        {
            uint8 suppliedUnderlyingDecimals = ERC20(vars.suppliedUnderlying).decimals();
            uint256 minValueToSupply = NMAX *
                (suppliedUnderlyingDecimals > 8 ? 10**(suppliedUnderlyingDecimals - 8) : 1);
            hevm.assume(
                _suppliedAmount >= minValueToSupply &&
                    minValueToSupply < comptroller.borrowCaps(vars.suppliedCToken)
            );
        }

        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amountPerBorrower = _suppliedAmount / NMAX;
        uint256 collateralAmount = ERC20(vars.collateralUnderlying).balanceOf(address(borrower1));

        {
            borrower1.approve(vars.collateralUnderlying, collateralAmount);
            borrower1.supply(vars.collateralCToken, collateralAmount);
            (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
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

    function testTemp() public {
        uint128 _suppliedAmount = 21;
        uint8 _collateralAsset = 3;
        uint8 _supplyAsset = 3;

        AssetVars memory vars;
        (vars.suppliedCToken, vars.suppliedUnderlying) = getAsset(_supplyAsset);
        (vars.collateralCToken, vars.collateralUnderlying) = getAsset(_collateralAsset);

        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amountPerBorrower = _suppliedAmount / NMAX;
        uint256 collateralAmount = ERC20(vars.collateralUnderlying).balanceOf(address(borrower1));

        {
            borrower1.approve(vars.collateralUnderlying, collateralAmount);
            borrower1.supply(vars.collateralCToken, collateralAmount);
            (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
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
