// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeLens is TestSetup {
    function testShouldPreserveOutdatedIndexes() public {
        Types.Indexes[] memory expectedIndexes = new Types.Indexes[](markets.length);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex)
            expectedIndexes[marketIndex] = lens.getIndexes(markets[marketIndex].poolToken, false);

        _upgrade();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];
            Types.Indexes memory indexes = lens.getIndexes(market.poolToken, false);

            assertEq(
                expectedIndexes[marketIndex].p2pSupplyIndex,
                indexes.p2pSupplyIndex,
                string.concat(market.symbol, " p2p supply index")
            );
            assertEq(
                expectedIndexes[marketIndex].p2pBorrowIndex,
                indexes.p2pBorrowIndex,
                string.concat(market.symbol, " p2p borrow index")
            );
            assertEq(
                expectedIndexes[marketIndex].poolSupplyIndex,
                indexes.poolSupplyIndex,
                string.concat(market.symbol, " pool supply index")
            );
            assertEq(
                expectedIndexes[marketIndex].poolBorrowIndex,
                indexes.poolBorrowIndex,
                string.concat(market.symbol, " pool borrow index")
            );
        }
    }

    function testShouldPreserveUpdatedIndexes() public {
        Types.Indexes[] memory expectedIndexes = new Types.Indexes[](markets.length);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex)
            expectedIndexes[marketIndex] = lens.getIndexes(markets[marketIndex].poolToken, true);

        _upgrade();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];
            Types.Indexes memory indexes = lens.getIndexes(market.poolToken, true);

            assertApproxEqAbs(
                expectedIndexes[marketIndex].p2pSupplyIndex,
                indexes.p2pSupplyIndex,
                3e8,
                string.concat(market.symbol, " p2p supply index")
            );
            assertApproxEqAbs(
                expectedIndexes[marketIndex].p2pBorrowIndex,
                indexes.p2pBorrowIndex,
                3e8,
                string.concat(market.symbol, " p2p borrow index")
            );
            assertApproxEqAbs(
                expectedIndexes[marketIndex].poolSupplyIndex,
                indexes.poolSupplyIndex,
                1,
                string.concat(market.symbol, " pool supply index")
            );
            assertApproxEqAbs(
                expectedIndexes[marketIndex].poolBorrowIndex,
                indexes.poolBorrowIndex,
                1,
                string.concat(market.symbol, " pool borrow index")
            );
        }
    }
}
