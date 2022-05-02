// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

contract TestSupplyFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    struct AssetVars {
        address suppliedAsset;
        address suppliedUnderlying;
        address borrowedAsset;
        address borrowedUnderlying;
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

    function testSupply2Fuzzed(
        uint128 _suppliedAmount,
        uint8 _randomModulo,
        uint8 _suppliedAsset,
        uint8 _borrowedAsset
    ) public {
        AssetVars memory vars;

        (vars.suppliedAsset, vars.suppliedUnderlying) = getAsset(_suppliedAsset);
        (vars.borrowedAsset, vars.borrowedUnderlying) = getAsset(_borrowedAsset);

        uint256 suppliedAmount = _suppliedAmount;

        hevm.assume(
            suppliedAmount > 0 &&
                suppliedAmount <=
                2 * ERC20(vars.suppliedUnderlying).balanceOf(address(borrower1)) &&
                _randomModulo > 0
        );

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedAsset, suppliedAmount);

        (, uint256 borrowable) = morpho.getUserMaxCapacitiesForAsset(
            address(borrower1),
            vars.borrowedAsset
        );
        uint256 borrowedAmount = (borrowable * _randomModulo) / 255;

        hevm.assume(
            borrowedAmount > 0 &&
                borrowedAmount <= ERC20(vars.borrowedUnderlying).balanceOf(address(borrower1))
        );
        borrower1.borrow(vars.borrowedAsset, borrowedAmount);

        borrower1.approve(vars.suppliedUnderlying, suppliedAmount);
        borrower1.supply(vars.suppliedAsset, suppliedAmount);
    }
}
