// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeable is TestSetup {
    /// Morpho ///

    function testUpgradeMorpho() public {
        _testUpgradeProxy(morphoProxy, address(new Morpho()));
    }

    function testOnlyProxyOwnerCanUpgradeMorpho() public {
        _testOnlyProxyOwnerCanUpgradeProxy(morphoProxy, address(new Morpho()));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallMorpho() public {
        _testOnlyProxyOwnerCanUpgradeAndCallProxy(morphoProxy, address(new Morpho()));
    }

    function testPositionsManagerImplementationsShouldBeInitialized() public {
        _testProxyImplementationShouldBeInitialized(address(morphoImplV1));

        hevm.expectRevert("Initializable: contract is already initialized");
        morphoImplV1.initialize(
            entryPositionsManager,
            exitPositionsManager,
            interestRatesManager,
            poolAddressesProvider,
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 3e6, repay: 3e6}),
            20
        );
    }

    function testEntryPositionsManagerImplementationShouldBeInitialized() public {
        _testProxyImplementationShouldBeInitialized(address(entryPositionsManager));
    }

    function testExitPositionsManagerImplementationShouldBeInitialized() public {
        _testProxyImplementationShouldBeInitialized(address(exitPositionsManager));
    }

    /// Lens ///

    function testUpgradeLens() public {
        _testUpgradeProxy(lensProxy, address(new Lens(address(morpho))));
    }

    function testOnlyProxyOwnerCanUpgradeLens() public {
        _testOnlyProxyOwnerCanUpgradeProxy(lensProxy, address(new Lens(address(morpho))));
    }

    function testOnlyProxyOwnerCanUpgradeAndCallLens() public {
        _testOnlyProxyOwnerCanUpgradeAndCallProxy(lensProxy, address(new Lens(address(morpho))));
    }

    /// INTERNAL ///
    function _testUpgradeProxy(TransparentUpgradeableProxy _proxy, address _impl) internal {
        hevm.record();
        proxyAdmin.upgrade(_proxy, _impl);
        (, bytes32[] memory writes) = hevm.accesses(address(_proxy));

        assertEq(writes.length, 1);
        assertEq(
            bytes32ToAddress(
                hevm.load(
                    address(_proxy),
                    bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
                )
            ),
            _impl
        );
    }

    function _testOnlyProxyOwnerCanUpgradeProxy(TransparentUpgradeableProxy _proxy, address _impl)
        internal
    {
        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(_proxy, _impl);

        proxyAdmin.upgrade(_proxy, _impl);
    }

    function _testOnlyProxyOwnerCanUpgradeAndCallProxy(
        TransparentUpgradeableProxy _proxy,
        address _impl
    ) internal {
        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgradeAndCall(_proxy, _impl, "");
    }

    function _testProxyImplementationShouldBeInitialized(address impl) public {
        assertEq(uint256(hevm.load(impl, 0)), 1);
    }
}
