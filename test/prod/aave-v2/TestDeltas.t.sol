// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestDeltas is TestSetup {
    using WadRayMath for uint256;

    struct DeltasTest {
        TestMarket market;
        //
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
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

    function testShouldClearP2P() public virtual {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            // _revert(); // TODO: re-add as soon as https://github.com/foundry-rs/foundry/issues/3792 is resolved, to avoid sharing state changes with each market test

            DeltasTest memory test;
            test.market = markets[marketIndex];

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyBefore,
                test.p2pBorrowBefore
            ) = morpho.deltas(test.market.poolToken);

            (
                test.p2pSupplyIndex,
                test.p2pBorrowIndex,
                test.poolSupplyIndex,
                test.poolBorrowIndex
            ) = lens.getIndexes(test.market.poolToken);

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
                1e15,
                "avg supply rate per year"
            );
            assertApproxEqAbs(
                test.avgBorrowRatePerYear,
                reserve.currentVariableBorrowRate,
                1e15,
                "avg borrow rate per year"
            );
        }
    }
}
