// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestUpgradeable is TestSetup {
    using CompoundMath for uint256;

    function testUpgradeMarketsManager() public {
        marketsManager.setReserveFactor(cDai, 1);

        MarketsManager marketsManagerImplV2 = new MarketsManager();
        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));

        // Should not change
        (uint16 reserveFactor, ) = marketsManager.marketParameters(cDai);
        assertEq(reserveFactor, 1);
    }

    function testUpgradePositionsManager() public {
        uint256 amount = 10000 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);
        uint256 supplyPoolIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(supplyPoolIndex);

        PositionsManager positionsManagerImplV2 = new PositionsManager();
        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));

        // Should not change
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPool, expectedOnPool);
    }

    function testOnlyProxyOwnerCanUpgradeMarketsManager() public {
        MarketsManager marketsManagerImplV2 = new MarketsManager();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));

        proxyAdmin.upgrade(marketsManagerProxy, address(marketsManagerImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallMarketsManager() public {
        MarketsManager marketsManagerImplV2 = new MarketsManager();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(marketsManagerProxy, address(marketsManagerImplV2), "");

        // Revert for wrong data not wrong caller
        hevm.expectRevert("Address: low-level delegate call failed");
        proxyAdmin.upgradeAndCall(marketsManagerProxy, address(marketsManagerImplV2), "");
    }

    function testOnlyProxyOwnerCanUpgradePositionsManager() public {
        PositionsManager positionsManagerImplV2 = new PositionsManager();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));

        proxyAdmin.upgrade(positionsManagerProxy, address(positionsManagerImplV2));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallPositionsManager() public {
        PositionsManager positionsManagerImplV2 = new PositionsManager();

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(
            positionsManagerProxy,
            payable(address(positionsManagerImplV2)),
            ""
        );

        // Revert for wrong data not wrong caller
        proxyAdmin.upgradeAndCall(
            positionsManagerProxy,
            payable(address(positionsManagerImplV2)),
            ""
        );
    }
}
