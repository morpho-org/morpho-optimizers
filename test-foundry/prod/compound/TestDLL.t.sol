// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestUpgradeV1_9 is TestSetup {
    using CompoundMath for uint256;

    function testShouldPreservePoolSuppliersDLL() public {
        for (uint256 marketIndex; marketIndex < borrowableCollateralMarkets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];

            address[] memory poolSuppliers = new address[](10_000);

            uint256 i;
            address next = morpho.getHead(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL);
            while (next != address(0)) {
                poolSuppliers[i] = next;
                next = morpho.getNext(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assembly {
                mstore(poolSuppliers, i)
            }

            vm.startPrank(address(proxyAdmin));
            morphoProxy.upgradeTo(address(new Morpho()));
            vm.stopPrank();

            vm.startPrank(morpho.owner());
            morpho.setPositionsManager(new PositionsManager());
            vm.stopPrank();

            i = 0;
            next = morpho.getHead(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL);
            while (next != address(0)) {
                assertEq(next, poolSuppliers[i]);

                next = morpho.getNext(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assertEq(i, poolSuppliers.length);
        }
    }

    function testShouldPreservePoolBorrowersDLL() public {
        for (uint256 marketIndex; marketIndex < borrowableCollateralMarkets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];

            address[] memory poolBorrowers = new address[](10_000);

            uint256 i;
            address next = morpho.getHead(market.poolToken, Types.PositionType.BORROWERS_ON_POOL);
            while (next != address(0)) {
                poolBorrowers[i] = next;
                next = morpho.getNext(market.poolToken, Types.PositionType.BORROWERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assembly {
                mstore(poolBorrowers, i)
            }

            vm.startPrank(address(proxyAdmin));
            morphoProxy.upgradeTo(address(new Morpho()));
            vm.stopPrank();

            vm.startPrank(morpho.owner());
            morpho.setPositionsManager(new PositionsManager());
            vm.stopPrank();

            i = 0;
            next = morpho.getHead(market.poolToken, Types.PositionType.BORROWERS_ON_POOL);
            while (next != address(0)) {
                assertEq(next, poolBorrowers[i]);

                next = morpho.getNext(market.poolToken, Types.PositionType.BORROWERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assertEq(i, poolBorrowers.length);
        }
    }

    function testShouldPreserveP2PSuppliersDLL() public {
        for (uint256 marketIndex; marketIndex < borrowableCollateralMarkets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];

            address[] memory p2pSuppliers = new address[](10_000);

            uint256 i;
            address next = morpho.getHead(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL);
            while (next != address(0)) {
                p2pSuppliers[i] = next;
                next = morpho.getNext(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assembly {
                mstore(p2pSuppliers, i)
            }

            vm.startPrank(address(proxyAdmin));
            morphoProxy.upgradeTo(address(new Morpho()));
            vm.stopPrank();

            vm.startPrank(morpho.owner());
            morpho.setPositionsManager(new PositionsManager());
            vm.stopPrank();

            i = 0;
            next = morpho.getHead(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL);
            while (next != address(0)) {
                assertEq(next, p2pSuppliers[i]);

                next = morpho.getNext(market.poolToken, Types.PositionType.SUPPLIERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assertEq(i, p2pSuppliers.length);
        }
    }

    function testShouldPreserveP2PBorrowersDLL() public {
        for (uint256 marketIndex; marketIndex < borrowableCollateralMarkets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];

            address[] memory p2pBorrowers = new address[](10_000);

            uint256 i;
            address next = morpho.getHead(market.poolToken, Types.PositionType.BORROWERS_ON_POOL);
            while (next != address(0)) {
                p2pBorrowers[i] = next;
                next = morpho.getNext(market.poolToken, Types.PositionType.BORROWERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assembly {
                mstore(p2pBorrowers, i)
            }

            vm.startPrank(address(proxyAdmin));
            morphoProxy.upgradeTo(address(new Morpho()));
            vm.stopPrank();

            vm.startPrank(morpho.owner());
            morpho.setPositionsManager(new PositionsManager());
            vm.stopPrank();

            i = 0;
            next = morpho.getHead(market.poolToken, Types.PositionType.BORROWERS_ON_POOL);
            while (next != address(0)) {
                assertEq(next, p2pBorrowers[i]);

                next = morpho.getNext(market.poolToken, Types.PositionType.BORROWERS_ON_POOL, next);

                unchecked {
                    ++i;
                }
            }

            assertEq(i, p2pBorrowers.length);
        }
    }
}
