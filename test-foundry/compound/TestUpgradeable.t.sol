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
        proxyAdmin.upgradeAndCall(morphoProxy, payable(address(morphoImplV2)), "");

        // Revert for wrong data not wrong caller
        proxyAdmin.upgradeAndCall(morphoProxy, payable(address(morphoImplV2)), "");
    }

    function testImplementationsShouldBeInitialized() public {
        Types.MaxGasForMatching memory defaultMaxGasForMatching = Types.MaxGasForMatching({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        // Test for Morpho Implementation.
        hevm.expectRevert("Initializable: contract is already initialized");
        morphoImplV1.initialize(
            positionsManager,
            interestRatesManager,
            comptroller,
            defaultMaxGasForMatching,
            1,
            20,
            cEth,
            wEth
        );

        // Test for PositionsManager Implementation.
        // `_initialized` value is at slot 0.
        uint256 _initialized = uint256(hevm.load(address(positionsManager), bytes32(0)));
        assertEq(_initialized, 1);
    }
}
