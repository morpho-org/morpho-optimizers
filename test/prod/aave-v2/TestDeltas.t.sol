// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestDeltas is TestSetup {
    using WadRayMath for uint256;

    struct DeltasTest {
        TestMarket market;
        Types.Indexes indexes;
        //
        uint256 p2pSupplyDelta;
        uint256 p2pBorrowDelta;
        //
        uint256 p2pSupplyBefore;
        uint256 p2pBorrowBefore;
        uint256 p2pSupplyAfter;
        uint256 p2pBorrowAfter;
        //
        uint256 morphoSupplyBefore;
        uint256 morphoBorrowBefore;
        //
        uint256 avgSupplyRatePerYear;
        uint256 avgBorrowRatePerYear;
    }

    function testShouldClearP2P() public virtual {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            // _revert(); // TODO: re-add as soon as https://github.com/foundry-rs/foundry/issues/3792 is resolved, to avoid sharing state changes with each market test

            DeltasTest memory test;
            test.market = markets[0];

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyBefore,
                test.p2pBorrowBefore
            ) = morpho.deltas(test.market.poolToken);

            test.indexes = lens.getIndexes(test.market.poolToken);

            uint256 p2pSupplyUnderlying = test.p2pSupplyBefore.rayMul(test.indexes.p2pSupplyIndex);
            uint256 p2pBorrowUnderlying = test.p2pBorrowBefore.rayMul(test.indexes.p2pBorrowIndex);
            uint256 supplyDeltaUnderlyingBefore = test.p2pSupplyDelta.rayMul(
                test.indexes.poolSupplyIndex
            );
            uint256 borrowDeltaUnderlyingBefore = test.p2pBorrowDelta.rayMul(
                test.indexes.poolBorrowIndex
            );
            if (
                p2pSupplyUnderlying <= supplyDeltaUnderlyingBefore ||
                p2pBorrowUnderlying <= borrowDeltaUnderlyingBefore
            ) continue;

            test.morphoSupplyBefore = IAToken(test.market.poolToken).balanceOf(address(morpho));
            test.morphoBorrowBefore = IVariableDebtToken(test.market.debtToken).balanceOf(
                address(morpho)
            );

            vm.prank(morpho.owner());
            morpho.increaseP2PDeltas(test.market.poolToken, type(uint256).max);

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyAfter,
                test.p2pBorrowAfter
            ) = morpho.deltas(test.market.poolToken);

            assertApproxEqAbs(
                test.p2pSupplyDelta.rayMul(test.indexes.poolSupplyIndex),
                p2pSupplyUnderlying,
                10,
                "p2p supply delta"
            );
            assertApproxEqAbs(
                test.p2pBorrowDelta.rayMul(test.indexes.poolBorrowIndex),
                p2pBorrowUnderlying,
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

            assertApproxEqAbs(
                p2pSupplyUnderlying - supplyDeltaUnderlyingBefore,
                IAToken(test.market.poolToken).balanceOf(address(morpho)) - test.morphoSupplyBefore,
                10,
                "morpho pool supply"
            );
            assertApproxEqAbs(
                p2pBorrowUnderlying - borrowDeltaUnderlyingBefore,
                IVariableDebtToken(test.market.debtToken).balanceOf(address(morpho)) -
                    test.morphoBorrowBefore,
                10,
                "morpho pool borrow"
            );
        }
    }

    function testShouldNotClearP2PWhenFullDelta() public virtual {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            // _revert(); // TODO: re-add as soon as https://github.com/foundry-rs/foundry/issues/3792 is resolved, to avoid sharing state changes with each market test

            DeltasTest memory test;
            test.market = markets[0];

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyBefore,
                test.p2pBorrowBefore
            ) = morpho.deltas(test.market.poolToken);

            test.indexes = lens.getIndexes(test.market.poolToken);

            uint256 p2pSupplyUnderlying = test.p2pSupplyBefore.rayMul(test.indexes.p2pSupplyIndex);
            uint256 p2pBorrowUnderlying = test.p2pBorrowBefore.rayMul(test.indexes.p2pBorrowIndex);
            uint256 supplyDeltaUnderlyingBefore = test.p2pSupplyDelta.rayMul(
                test.indexes.poolSupplyIndex
            );
            uint256 borrowDeltaUnderlyingBefore = test.p2pBorrowDelta.rayMul(
                test.indexes.poolBorrowIndex
            );
            if (
                p2pSupplyUnderlying > supplyDeltaUnderlyingBefore &&
                p2pBorrowUnderlying > borrowDeltaUnderlyingBefore
            ) continue;

            vm.prank(morpho.owner());
            vm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
            morpho.increaseP2PDeltas(test.market.poolToken, type(uint256).max);
        }
    }
}
