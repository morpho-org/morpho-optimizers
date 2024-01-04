// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeLens is TestSetup {
    using WadRayMath for uint256;

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

    function testNextRateShouldMatchRateAfterInteraction(uint96 _amount) public {
        _upgrade();

        for (
            uint256 supplyMarketIndex;
            supplyMarketIndex < collateralMarkets.length;
            ++supplyMarketIndex
        ) {
            TestMarket memory supplyMarket = collateralMarkets[supplyMarketIndex];

            if (supplyMarket.status.isSupplyPaused) continue;

            for (
                uint256 borrowMarketIndex;
                borrowMarketIndex < borrowableMarkets.length;
                ++borrowMarketIndex
            ) {
                _revert();

                TestMarket memory borrowMarket = borrowableMarkets[borrowMarketIndex];

                uint256 borrowedPrice = oracle.getAssetPrice(borrowMarket.underlying);
                uint256 borrowAmount = _boundBorrowAmount(borrowMarket, _amount, borrowedPrice);
                uint256 supplyAmount = _getMinimumCollateralAmount(
                    borrowAmount,
                    borrowedPrice,
                    borrowMarket.decimals,
                    oracle.getAssetPrice(supplyMarket.underlying),
                    supplyMarket.decimals,
                    supplyMarket.ltv
                ).wadMul(1.001 ether);

                (uint256 expectedSupplyRate, , , ) = lens.getNextUserSupplyRatePerYear(
                    supplyMarket.poolToken,
                    address(user),
                    supplyAmount
                );

                _tip(supplyMarket.underlying, address(user), supplyAmount);

                user.approve(supplyMarket.underlying, supplyAmount);
                user.supply(supplyMarket.poolToken, address(user), supplyAmount, 1_000); // Only perform 1 matching loop, as simulated in getNextUserSupplyRatePerYear.

                assertApproxEqAbs(
                    lens.getCurrentUserSupplyRatePerYear(supplyMarket.poolToken, address(user)),
                    expectedSupplyRate,
                    1e15,
                    string.concat(supplyMarket.symbol, " supply rate")
                );

                if (borrowMarket.status.isBorrowPaused) continue;

                (uint256 expectedBorrowRate, , , ) = lens.getNextUserBorrowRatePerYear(
                    borrowMarket.poolToken,
                    address(user),
                    borrowAmount
                );

                user.borrow(borrowMarket.poolToken, borrowAmount, 1_000); // Only perform 1 matching loop, as simulated in getNextUserBorrowRatePerYear.

                assertApproxEqAbs(
                    lens.getCurrentUserBorrowRatePerYear(borrowMarket.poolToken, address(user)),
                    expectedBorrowRate,
                    1e15,
                    string.concat(borrowMarket.symbol, " borrow rate")
                );
            }
        }
    }
}
