// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

contract TestSupplyFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    function testSupplyFuzzed(uint128 _amount, uint8 _asset) public {
        (address asset, address underlying) = getAsset(_asset);

        uint256 amount = _amount;

        hevm.assume(amount > 0 && amount <= ERC20(underlying).balanceOf(address(supplier1)));

        supplier1.approve(underlying, amount);
        supplier1.supply(asset, amount);

        uint256 supplyPoolIndex = ICToken(asset).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(supplyPoolIndex);

        assertApproxEq(
            IERC20(asset).balanceOf(address(positionsManager)),
            expectedOnPool,
            5,
            "balance of cToken"
        );

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            asset,
            address(supplier1)
        );

        assertApproxEq(onPool, ICToken(asset).balanceOf(address(positionsManager)), 5, "on pool");
        assertApproxEq(onPool, expectedOnPool, 5, "on pool");
        assertEq(inP2P, 0, "in P2P");
    }
}
