// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeDLL is TestSetup {
    function _testUpgradeShouldPreservePriorityQueue(Types.PositionType queueType) internal {
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

            _upgrade();

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

    function testUpgradeShouldPreservePoolSuppliersDLL() public {
        _testUpgradeShouldPreservePriorityQueue(Types.PositionType.SUPPLIERS_ON_POOL);
    }

    function testUpgradeShouldPreservePoolBorrowersDLL() public {
        _testUpgradeShouldPreservePriorityQueue(Types.PositionType.BORROWERS_ON_POOL);
    }

    function testUpgradeShouldPreserveP2PSuppliersDLL() public {
        _testUpgradeShouldPreservePriorityQueue(Types.PositionType.SUPPLIERS_IN_P2P);
    }

    function testUpgradeShouldPreserveP2PBorrowersDLL() public {
        _testUpgradeShouldPreservePriorityQueue(Types.PositionType.BORROWERS_IN_P2P);
    }
}
