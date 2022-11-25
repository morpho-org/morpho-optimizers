// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeDeltas is TestSetup {
    using WadRayMath for uint256;

    struct DeltasTest {
        TestMarket market;
        //
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint112 poolSupplyIndex;
        uint112 poolBorrowIndex;
        //
        uint256 p2pSupplyDelta;
        uint256 p2pBorrowDelta;
        //
        uint256 p2pSupplyBefore;
        uint256 p2pBorrowBefore;
        uint256 p2pSupplyAfter;
        uint256 p2pBorrowAfter;
        //
        uint256 avgSupplyRatePerYear;
        uint256 avgBorrowRatePerYear;
    }

    function _onSetUp() internal override {
        super._onSetUp();

        _upgrade();
    }

    function testShouldClearP2P() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            _revert();

            DeltasTest memory test;
            test.market = activeMarkets[marketIndex];

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyBefore,
                test.p2pBorrowBefore
            ) = morpho.deltas(test.market.poolToken);

            test.p2pSupplyIndex = morpho.p2pSupplyIndex(test.market.poolToken);
            test.p2pBorrowIndex = morpho.p2pBorrowIndex(test.market.poolToken);
            (, test.poolSupplyIndex, test.poolBorrowIndex) = morpho.poolIndexes(
                test.market.poolToken
            );

            if (
                test.p2pSupplyBefore.rayMul(test.p2pSupplyIndex) <=
                test.p2pSupplyDelta.rayMul(test.poolSupplyIndex) ||
                test.p2pBorrowBefore.rayMul(test.p2pBorrowIndex) <=
                test.p2pBorrowDelta.rayMul(test.poolBorrowIndex)
            ) continue;

            vm.prank(morphoDao);
            morpho.increaseP2PDeltas(test.market.poolToken, type(uint256).max);

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyAfter,
                test.p2pBorrowAfter
            ) = morpho.deltas(test.market.poolToken);

            test.p2pSupplyIndex = morpho.p2pSupplyIndex(test.market.poolToken);
            test.p2pBorrowIndex = morpho.p2pBorrowIndex(test.market.poolToken);
            (, test.poolSupplyIndex, test.poolBorrowIndex) = morpho.poolIndexes(
                test.market.poolToken
            );

            assertApproxEqAbs(
                test.p2pSupplyDelta.rayMul(test.poolSupplyIndex),
                test.p2pSupplyBefore.rayMul(test.p2pSupplyIndex),
                10,
                "p2p supply delta"
            );
            assertApproxEqAbs(
                test.p2pBorrowDelta.rayMul(test.poolBorrowIndex),
                test.p2pBorrowBefore.rayMul(test.p2pBorrowIndex),
                10,
                "p2p borrow delta"
            );
            assertEq(test.p2pSupplyAfter, test.p2pSupplyBefore, "p2p supply");
            assertEq(test.p2pBorrowAfter, test.p2pBorrowBefore, "p2p borrow");

            (test.avgSupplyRatePerYear, , ) = lens.getAverageSupplyRatePerYear(
                test.market.poolToken
            );
            (test.avgBorrowRatePerYear, , ) = lens.getAverageBorrowRatePerYear(
                test.market.poolToken
            );
            DataTypes.ReserveData memory reserve = pool.getReserveData(test.market.underlying);

            assertApproxEqAbs(
                test.avgSupplyRatePerYear,
                reserve.currentLiquidityRate,
                10**(19 - test.market.decimals),
                "avg supply rate per year"
            );
            assertApproxEqAbs(
                test.avgBorrowRatePerYear,
                reserve.currentVariableBorrowRate,
                10**(22 - test.market.decimals),
                "avg borrow rate per year"
            );
        }
    }
}
