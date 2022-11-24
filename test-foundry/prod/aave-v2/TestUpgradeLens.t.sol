// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeLens is TestSetup {
    struct Indexes {
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
    }

    function testShouldPreserveIndexes() public {
        Indexes[] memory expectedIndexes = new Indexes[](markets.length);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            (
                uint256 p2pSupplyIndex,
                uint256 p2pBorrowIndex,
                uint256 poolSupplyIndex,
                uint256 poolBorrowIndex
            ) = lens.getIndexes(markets[marketIndex].poolToken);

            expectedIndexes[marketIndex].p2pSupplyIndex = p2pSupplyIndex;
            expectedIndexes[marketIndex].p2pBorrowIndex = p2pBorrowIndex;
            expectedIndexes[marketIndex].poolSupplyIndex = poolSupplyIndex;
            expectedIndexes[marketIndex].poolBorrowIndex = poolBorrowIndex;
        }

        _upgrade();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];
            (
                uint256 p2pSupplyIndex,
                uint256 p2pBorrowIndex,
                uint256 poolSupplyIndex,
                uint256 poolBorrowIndex
            ) = lens.getIndexes(market.poolToken);

            assertApproxEqAbs(
                expectedIndexes[marketIndex].p2pSupplyIndex,
                p2pSupplyIndex,
                1,
                string.concat(market.symbol, " p2p supply index")
            );
            assertApproxEqAbs(
                expectedIndexes[marketIndex].p2pBorrowIndex,
                p2pBorrowIndex,
                1e7,
                string.concat(market.symbol, " p2p borrow index")
            );
            assertApproxEqAbs(
                expectedIndexes[marketIndex].poolSupplyIndex,
                poolSupplyIndex,
                1,
                string.concat(market.symbol, " pool supply index")
            );
            assertApproxEqAbs(
                expectedIndexes[marketIndex].poolBorrowIndex,
                poolBorrowIndex,
                1,
                string.concat(market.symbol, " pool borrow index")
            );
        }
    }
}
