// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestDeltas is TestSetup {
    using CompoundMath for uint256;

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
        uint256 avgSupplyRatePerBlock;
        uint256 avgBorrowRatePerBlock;
    }

    function testShouldClearP2P() public virtual {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            // _revert(); // TODO: re-add as soon as https://github.com/foundry-rs/foundry/issues/3792 is resolved, to avoid sharing state changes with each market test

            DeltasTest memory test;
            test.market = markets[marketIndex];

            if (test.market.mintGuardianPaused || test.market.borrowGuardianPaused) continue;

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyBefore,
                test.p2pBorrowBefore
            ) = morpho.deltas(test.market.poolToken);

            test.indexes = lens.getIndexes(test.market.poolToken, true);

            uint256 p2pSupplyUnderlying = test.p2pSupplyBefore.mul(test.indexes.p2pSupplyIndex);
            uint256 p2pBorrowUnderlying = test.p2pBorrowBefore.mul(test.indexes.p2pBorrowIndex);
            uint256 supplyDeltaUnderlyingBefore = test.p2pSupplyDelta.mul(
                test.indexes.poolSupplyIndex
            );
            uint256 borrowDeltaUnderlyingBefore = test.p2pBorrowDelta.mul(
                test.indexes.poolBorrowIndex
            );
            if (
                p2pSupplyUnderlying <= supplyDeltaUnderlyingBefore ||
                p2pBorrowUnderlying <= borrowDeltaUnderlyingBefore
            ) continue;

            test.morphoSupplyBefore = ICToken(test.market.poolToken).balanceOfUnderlying(
                address(morpho)
            );
            test.morphoBorrowBefore = ICToken(test.market.poolToken).borrowBalanceCurrent(
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
                test.p2pSupplyDelta.mul(test.indexes.poolSupplyIndex),
                p2pSupplyUnderlying,
                10**(test.market.decimals / 2 + 1),
                "p2p supply delta"
            );
            assertApproxEqAbs(
                test.p2pBorrowDelta.mul(test.indexes.poolBorrowIndex),
                p2pBorrowUnderlying,
                10,
                "p2p borrow delta"
            );
            assertEq(test.p2pSupplyAfter, test.p2pSupplyBefore, "p2p supply");
            assertEq(test.p2pBorrowAfter, test.p2pBorrowBefore, "p2p borrow");

            (test.avgSupplyRatePerBlock, , ) = lens.getAverageSupplyRatePerBlock(
                test.market.poolToken
            );
            (test.avgBorrowRatePerBlock, , ) = lens.getAverageBorrowRatePerBlock(
                test.market.poolToken
            );

            assertApproxEqAbs(
                test.avgSupplyRatePerBlock,
                ICToken(test.market.poolToken).supplyRatePerBlock(),
                10,
                "avg supply rate per year"
            );
            assertApproxEqAbs(
                test.avgBorrowRatePerBlock,
                ICToken(test.market.poolToken).borrowRatePerBlock(),
                10,
                "avg borrow rate per year"
            );

            assertApproxEqAbs(
                p2pSupplyUnderlying - supplyDeltaUnderlyingBefore,
                ICToken(test.market.poolToken).balanceOfUnderlying(address(morpho)) -
                    test.morphoSupplyBefore,
                10**(test.market.decimals / 2 + 1),
                "morpho pool supply"
            );
            assertApproxEqAbs(
                p2pBorrowUnderlying - borrowDeltaUnderlyingBefore,
                ICToken(test.market.poolToken).borrowBalanceCurrent(address(morpho)) -
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
            test.market = markets[marketIndex];

            if (test.market.mintGuardianPaused || test.market.borrowGuardianPaused) continue;

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyBefore,
                test.p2pBorrowBefore
            ) = morpho.deltas(test.market.poolToken);

            test.indexes = lens.getIndexes(test.market.poolToken, true);

            uint256 p2pSupplyUnderlying = test.p2pSupplyBefore.mul(test.indexes.p2pSupplyIndex);
            uint256 p2pBorrowUnderlying = test.p2pBorrowBefore.mul(test.indexes.p2pBorrowIndex);
            uint256 supplyDeltaUnderlyingBefore = test.p2pSupplyDelta.mul(
                test.indexes.poolSupplyIndex
            );
            uint256 borrowDeltaUnderlyingBefore = test.p2pBorrowDelta.mul(
                test.indexes.poolBorrowIndex
            );
            if (
                p2pSupplyUnderlying > supplyDeltaUnderlyingBefore &&
                p2pBorrowUnderlying > borrowDeltaUnderlyingBefore
            ) {
                continue;
            }

            vm.prank(morpho.owner());
            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            morpho.increaseP2PDeltas(test.market.poolToken, type(uint256).max);
        }
    }
}
