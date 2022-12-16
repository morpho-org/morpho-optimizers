// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeLens is TestSetup {
    function testShouldPreserveIndexes() public {
        Types.Indexes[] memory expectedIndexes = new Types.Indexes[](markets.length);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex)
            expectedIndexes[marketIndex] = lens.getIndexes(markets[marketIndex].poolToken);

        _upgrade();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            TestMarket memory market = markets[marketIndex];
            Types.Indexes memory indexes = lens.getIndexes(market.poolToken);

            assertApproxEqAbs(
                expectedIndexes[marketIndex].p2pSupplyIndex,
                indexes.p2pSupplyIndex,
                1,
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
