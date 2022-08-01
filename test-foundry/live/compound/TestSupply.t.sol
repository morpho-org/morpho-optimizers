// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using CompoundMath for uint256;

    function testShouldSupplyAmountP2PAndOnPool(uint256 amount) public {
        vm.assume(amount >= 1e9 && amount <= ERC20(dai).balanceOf(address(supplier1)));

        uint256 morphoDaiBalanceBefore = ERC20(dai).balanceOf(address(morpho));
        uint256 morphoBalanceOnPoolBefore = ERC20(cDai).balanceOf(address(morpho));

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        assertEq(
            onPool.mul(poolSupplyIndex) + inP2P.mul(p2pSupplyIndex),
            amount.div(poolSupplyIndex).mul(poolSupplyIndex), // rounding errors
            "unexpected supplied amount"
        );
        assertEq(
            ERC20(dai).balanceOf(address(morpho)),
            morphoDaiBalanceBefore,
            "unexpected morpho DAI balance"
        );
        assertEq(
            ERC20(cDai).balanceOf(address(morpho)) - morphoBalanceOnPoolBefore,
            onPool,
            "unexpected DAI balance on pool"
        );
    }
}
