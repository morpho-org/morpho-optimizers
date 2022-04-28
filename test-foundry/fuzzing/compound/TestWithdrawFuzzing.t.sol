// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./TestSetupFuzzing.sol";

contract TestWithdrawFuzzing is TestSetupFuzzing {
    using CompoundMath for uint256;

    function testWithdrawFuzzed(
        uint128 _suppliedAmount,
        uint128 _withdrawnAmount,
        uint8 _asset
    ) public {
        (address asset, address underlying) = getAsset(_asset);

        uint256 suppliedAmount = _suppliedAmount;
        uint256 withdrawnAmount = _withdrawnAmount;

        hevm.assume(
            suppliedAmount > 0 &&
                withdrawnAmount > 0 &&
                suppliedAmount > withdrawnAmount &&
                suppliedAmount <= ERC20(underlying).balanceOf(address(supplier1))
        );
        supplier1.approve(underlying, suppliedAmount);
        supplier1.supply(asset, suppliedAmount);

        supplier1.withdraw(asset, withdrawnAmount);

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            asset,
            address(supplier1)
        );

        uint256 supplyPoolIndex = ICToken(asset).exchangeRateCurrent();
        uint256 expectedOnPool = (suppliedAmount - withdrawnAmount).div(supplyPoolIndex);

        assertApproxEq(onPool, ICToken(asset).balanceOf(address(positionsManager)), 5, "on pool");
        assertApproxEq(onPool, expectedOnPool, 5, "on pool");
        assertEq(inP2P, 0, "in P2P");
    }
}
