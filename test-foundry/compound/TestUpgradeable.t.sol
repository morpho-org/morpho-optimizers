// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestUpgradeable is TestSetup {
    using CompoundMath for uint256;

    function testUpgradeMorpho() public {
        uint256 amount = 10000 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);
        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(poolSupplyIndex);

        Morpho morphoImplV2 = new Morpho();
        proxyAdmin.upgrade(morphoProxy, address(morphoImplV2));

        // Should not change
        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    function testOnlyProxyOwnerCanUpgradeMorpho() public {
        Morpho morphoImplV2 = new Morpho();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(morphoProxy, address(morphoImplV2));

        proxyAdmin.upgrade(morphoProxy, address(morphoImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallMorpho() public {
        Morpho morphoImplV2 = new Morpho();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(morphoProxy, payable(address(morphoImplV2)), "");

        // Revert for wrong data not wrong caller
        proxyAdmin.upgradeAndCall(morphoProxy, payable(address(morphoImplV2)), "");
    }
}
