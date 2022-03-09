// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestUpgradeable is TestSetup {
    function test_upgrade_markets_manager() public {
        marketsManager.setReserveFactor(aDai, 1);

        MarketsManagerForAave marketsManagerImplV2 = new MarketsManagerForAave();
        marketsManager.upgradeTo(address(marketsManagerImplV2));

        // Should not change
        assertEq(marketsManager.reserveFactor(aDai), 1);
    }

    function test_upgrade_positions_manager() public {
        uint256 amount = 10000 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = underlyingToScaledBalance(amount, normalizedIncome);

        PositionsManagerForAave positionsManagerImplV2 = new PositionsManagerForAave();
        positionsManager.upgradeTo(address(positionsManagerImplV2));

        // Should not change
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        testEquality(onPool, expectedOnPool);
    }

    function test_only_owner_of_proxy_admin_can_upgrade_markets_manager() public {
        MarketsManagerForAave marketsManagerImplV2 = new MarketsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        marketsManager.upgradeTo(address(marketsManagerImplV2));

        marketsManager.upgradeTo(address(marketsManagerImplV2));
    }

    function test_only_owner_of_proxy_admin_can_upgrade_and_call_markets_manager() public {
        MarketsManagerForAave marketsManagerImplV2 = new MarketsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        marketsManager.upgradeToAndCall(address(marketsManagerImplV2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        marketsManager.upgradeToAndCall(address(marketsManagerImplV2), "");
    }

    function test_only_owner_of_proxy_admin_can_upgrade_positions_manager() public {
        PositionsManagerForAave positionsManager2 = new PositionsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        positionsManager.upgradeTo(address(positionsManager2));

        positionsManager.upgradeTo(address(positionsManager2));
    }

    function test_only_owner_of_proxy_admin_can_upgrade_and_call_positions_manager() public {
        PositionsManagerForAave positionsManager2 = new PositionsManagerForAave();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        positionsManager.upgradeToAndCall(address(positionsManager2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        positionsManager.upgradeToAndCall(address(positionsManager2), "");
    }
}
