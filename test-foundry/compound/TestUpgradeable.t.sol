// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestUpgradeable is TestSetup {
    function testUpgradeMarketsManager() public {
        marketsManager.setReserveFactor(cDai, 1);

        MarketsManagerForCompound marketsManagerImplV2 = new MarketsManagerForCompound();
        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));

        // Should not change
        assertEq(marketsManager.reserveFactor(cDai), 1);
    }

    function testUpgradePositionsManager() public {
        uint256 amount = 10000 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);
        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = underlyingToPoolSupplyBalance(amount, supplyPoolIndex);

        PositionsManagerForCompound positionsManagerImplV2 = new PositionsManagerForCompound();
        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));

        // Should not change
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    function testOnlyProxyOwnerCanUpgradeMarketsManager() public {
        MarketsManagerForCompound marketsManagerImplV2 = new MarketsManagerForCompound();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));

        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallMarketsManager() public {
        MarketsManagerForCompound marketsManagerImplV2 = new MarketsManagerForCompound();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(marketsManagerProxy, address(marketsManagerImplV2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        proxyAdmin.upgradeAndCall(marketsManagerProxy, address(marketsManagerImplV2), "");
    }

    function testOnlyProxyOwnerCanUpgradePositionsManager() public {
        PositionsManagerForCompound positionsManagerImplV2 = new PositionsManagerForCompound();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));

        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallPositionsManager() public {
        PositionsManagerForCompound positionsManagerImplV2 = new PositionsManagerForCompound();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(positionsManagerProxy, address(positionsManagerImplV2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        proxyAdmin.upgradeAndCall(positionsManagerProxy, address(positionsManagerImplV2), "");
    }
}
