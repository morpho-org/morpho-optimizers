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
        assertApproxEq(onPool, 1, expectedOnPool);
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
            entryManager,
            exitManager,
            interestRatesManager,
            ILendingPoolAddressesProvider(lendingPoolAddressesProviderAddress),
            defaultMaxGasForMatching,
            20
        );

        // Test for EntryManager Implementation.
        // `_initialized` value is at slot 0.
        uint256 _initialized = uint256(hevm.load(address(entryManager), bytes32(0)));
        assertEq(_initialized, 1);

        // Test for ExitManager Implementation.
        // `_initialized` value is at slot 0.
        _initialized = uint256(hevm.load(address(exitManager), bytes32(0)));
        assertEq(_initialized, 1);
    }
}
