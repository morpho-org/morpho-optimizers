// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestUpgradeable is TestSetup {
    function testUpgradeMorpho() public {
        uint256 amount = 10_000 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = underlyingToScaledBalance(amount, normalizedIncome);

        Morpho morphoImplV2 = new Morpho();
        proxyAdmin.upgrade(morphoProxy, address(morphoImplV2));

        // Should not change
        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(onPool, expectedOnPool);
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
        proxyAdmin.upgradeAndCall(morphoProxy, address(morphoImplV2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        proxyAdmin.upgradeAndCall(morphoProxy, address(morphoImplV2), "");
    }
}
