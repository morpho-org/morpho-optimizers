// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestUpgradeable is TestSetup {
    function testUpgradeMarketsManager() public {
        marketsManager.setReserveFactor(aDai, 1);

        MarketsManagerForAave marketsManagerImplV2 = new MarketsManagerForAave();
        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));

        // Should not change
        assertEq(marketsManager.reserveFactor(aDai), 1);
    }

    function testUpgradePositionsManager() public {
        uint256 amount = 10_000 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = underlyingToScaledBalance(amount, normalizedIncome);

        PositionsManagerForAave positionsManagerImplV2 = new PositionsManagerForAave();
        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));

        // Should not change
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    function testOnlyProxyOwnerCanUpgradeMarketsManager() public {
        MarketsManagerForAave marketsManagerImplV2 = new MarketsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));

        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallMarketsManager() public {
        MarketsManagerForAave marketsManagerImplV2 = new MarketsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(marketsManagerProxy, address(marketsManagerImplV2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        proxyAdmin.upgradeAndCall(marketsManagerProxy, address(marketsManagerImplV2), "");
    }

    function testOnlyProxyOwnerCanUpgradePositionsManager() public {
        PositionsManagerForAave positionsManagerImplV2 = new PositionsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));

        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallPositionsManager() public {
        PositionsManagerForAave positionsManagerImplV2 = new PositionsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(positionsManagerProxy, address(positionsManagerImplV2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        proxyAdmin.upgradeAndCall(positionsManagerProxy, address(positionsManagerImplV2), "");
    }
}
