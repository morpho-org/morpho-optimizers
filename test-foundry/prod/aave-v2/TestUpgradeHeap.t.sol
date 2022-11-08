// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeHeap is TestSetup {
    function _testShouldPreservePriorityQueue(Types.PositionType queueType) internal {
        for (uint256 marketIndex; marketIndex < borrowableCollateralMarkets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];

            address[] memory priorityQueue = new address[](10_000);

            uint256 i;
            address next = morpho.getHead(market.poolToken, queueType);
            while (next != address(0)) {
                priorityQueue[i] = next;
                next = morpho.getNext(market.poolToken, queueType, next);

                ++i;
            }

            assembly {
                mstore(priorityQueue, i)
            }

            vm.startPrank(morphoDao);
            proxyAdmin.upgrade(morphoProxy, address(new Morpho()));
            morpho.setEntryPositionsManager(new EntryPositionsManager());
            morpho.setExitPositionsManager(new ExitPositionsManager());
            vm.stopPrank();

            i = 0;
            next = morpho.getHead(market.poolToken, queueType);
            while (next != address(0)) {
                assertEq(next, priorityQueue[i]);

                next = morpho.getNext(market.poolToken, queueType, next);

                ++i;
            }

            assertEq(i, priorityQueue.length);
        }
    }

    function testShouldPreservePoolSuppliersDLL() public {
        _testShouldPreservePriorityQueue(Types.PositionType.SUPPLIERS_ON_POOL);
    }

    function testShouldPreservePoolBorrowersDLL() public {
        _testShouldPreservePriorityQueue(Types.PositionType.BORROWERS_ON_POOL);
    }

    function testShouldPreserveP2PSuppliersDLL() public {
        _testShouldPreservePriorityQueue(Types.PositionType.SUPPLIERS_IN_P2P);
    }

    function testShouldPreserveP2PBorrowersDLL() public {
        _testShouldPreservePriorityQueue(Types.PositionType.BORROWERS_IN_P2P);
    }
}
