// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using WadRayMath for uint256;

    struct SupplyTest {
        TestMarket market;
        //
        uint256 morphoSuppliedOnPoolBefore;
        uint256 morphoBorrowedOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        //
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        //
        bool p2pDisabled;
        uint256 p2pBorrowDelta;
        //
        uint256 supplyRatePerYear;
        uint256 p2pSupplyRatePerYear;
        uint256 poolSupplyRatePerYear;
        //
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        //
        uint256 unclaimedRewardsBefore;
        //
        uint256 underlyingOnPoolBefore;
        uint256 underlyingInP2PBefore;
        uint256 totalUnderlyingBefore;
        //
        uint256 underlyingOnPoolAfter;
        uint256 underlyingInP2PAfter;
        uint256 totalUnderlyingAfter;
    }

    function _testShouldSupplyMarketP2PAndOnPool(TestMarket memory _market, uint96 _amount)
        internal
    {
        SupplyTest memory test;
        test.market = _market;

        (, test.p2pBorrowDelta, , ) = morpho.deltas(_market.poolToken);
        (, , , , , , test.p2pDisabled) = morpho.market(_market.poolToken);
        test.morphoSuppliedOnPoolBefore = ERC20(_market.poolToken).balanceOf(address(morpho));
        test.morphoBorrowedOnPoolBefore = ERC20(_market.debtToken).balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = ERC20(_market.underlying).balanceOf(address(morpho));

        uint256 amount = bound(
            _amount,
            10**(_market.decimals - 6),
            ERC20(_market.underlying).balanceOf(address(this))
        );
        if (_market.underlying == uni || _market.underlying == comp)
            amount = uint96(uint80(amount)); // avoids overflows

        _tip(_market.underlying, address(user), amount);

        user.approve(_market.underlying, amount);
        user.supply(_market.poolToken, address(user), amount);

        test.p2pSupplyIndex = morpho.p2pSupplyIndex(_market.poolToken);
        (, test.poolSupplyIndex, test.poolBorrowIndex) = morpho.poolIndexes(_market.poolToken);
        test.supplyRatePerYear = lens.getCurrentUserSupplyRatePerYear(
            _market.poolToken,
            address(user)
        );
        (test.p2pSupplyRatePerYear, , test.poolSupplyRatePerYear, ) = lens.getRatesPerYear(
            _market.poolToken
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.supplyBalanceInOf(
            _market.poolToken,
            address(user)
        );

        test.underlyingInP2PBefore = test.balanceInP2P.rayMul(test.p2pSupplyIndex);
        test.underlyingOnPoolBefore = test.balanceOnPool.rayMul(test.poolSupplyIndex);
        test.totalUnderlyingBefore = test.underlyingOnPoolBefore + test.underlyingInP2PBefore;

        assertEq(
            ERC20(_market.underlying).balanceOf(address(user)),
            0,
            "unexpected underlying balance after"
        );
        assertApproxEqAbs(
            test.totalUnderlyingBefore,
            amount,
            1,
            "unexpected total supplied amount"
        );
        if (test.p2pDisabled) assertEq(test.balanceInP2P, 0, "expected no match");

        address[] memory poolTokens = new address[](1);
        poolTokens[0] = _market.poolToken;
        if (address(rewardsManager) != address(0)) {
            test.unclaimedRewardsBefore = rewardsManager.getUserUnclaimedRewards(
                poolTokens,
                address(user)
            );

            assertEq(test.unclaimedRewardsBefore, 0, "unclaimed rewards not zero");
        }

        assertEq(
            ERC20(_market.underlying).balanceOf(address(morpho)),
            test.morphoUnderlyingBalanceBefore,
            "unexpected morpho underlying balance"
        );
        assertApproxEqAbs(
            ERC20(_market.poolToken).balanceOf(address(morpho)),
            test.morphoSuppliedOnPoolBefore + test.underlyingOnPoolBefore,
            1,
            "unexpected morpho supply balance on pool"
        );
        assertApproxEqAbs(
            ERC20(_market.debtToken).balanceOf(address(morpho)) + test.underlyingInP2PBefore,
            test.morphoBorrowedOnPoolBefore,
            1,
            "unexpected morpho borrow balance on pool"
        );

        if (test.p2pBorrowDelta.rayMul(test.poolBorrowIndex) <= amount)
            assertGe(
                test.underlyingInP2PBefore,
                test.p2pBorrowDelta.rayMul(test.poolBorrowIndex),
                "expected p2p borrow delta minimum match"
            );
        else
            assertApproxEqAbs(
                test.underlyingInP2PBefore,
                amount,
                1,
                "expected p2p borrow delta full match"
            );

        vm.roll(block.number + 500);
        vm.warp(block.timestamp + 1.5 hours);

        morpho.updateIndexes(_market.poolToken);

        vm.roll(block.number + 500);
        vm.warp(block.timestamp + 1.5 hours);

        (test.underlyingInP2PAfter, test.underlyingOnPoolAfter, test.totalUnderlyingAfter) = lens
        .getCurrentSupplyBalanceInOf(_market.poolToken, address(user));

        uint256 expectedUnderlyingOnPoolAfter = test.underlyingOnPoolBefore.rayMul(
            1e27 + (test.poolSupplyRatePerYear * 3 hours) / 365 days
        );
        uint256 expectedUnderlyingInP2PAfter = test.underlyingInP2PBefore.rayMul(
            1e27 + (test.p2pSupplyRatePerYear * 3 hours) / 365 days
        );
        uint256 expectedTotalUnderlyingAfter = test.totalUnderlyingBefore.rayMul(
            1e27 + (test.supplyRatePerYear * 3 hours) / 365 days
        );

        assertApproxEqAbs(
            test.underlyingOnPoolAfter,
            expectedUnderlyingOnPoolAfter,
            test.underlyingOnPoolAfter / 1e7 + 1e4,
            "unexpected pool underlying amount"
        );
        assertApproxEqAbs(
            test.underlyingInP2PAfter,
            expectedUnderlyingInP2PAfter,
            test.underlyingInP2PAfter / 1e7 + 1e4,
            "unexpected p2p underlying amount"
        );
        assertApproxEqAbs(
            test.totalUnderlyingAfter,
            expectedTotalUnderlyingAfter,
            test.totalUnderlyingAfter / 1e7 + 1e4,
            "unexpected total underlying amount from avg supply rate"
        );
        assertApproxEqAbs(
            test.totalUnderlyingAfter,
            expectedUnderlyingOnPoolAfter + expectedUnderlyingInP2PAfter,
            test.totalUnderlyingBefore / 1e7 + 1e4,
            "unexpected total underlying amount"
        );
        if (
            address(rewardsManager) != address(0) &&
            test.underlyingOnPoolAfter > 0 &&
            block.timestamp < aaveIncentivesController.DISTRIBUTION_END()
        )
            assertGt(
                rewardsManager.getUserUnclaimedRewards(poolTokens, address(user)),
                test.unclaimedRewardsBefore,
                "lower unclaimed rewards"
            );
    }

    function testShouldSupplyAllMarketsP2PAndOnPool(uint96 _amount) public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            if (snapshotId < type(uint256).max) vm.revertTo(snapshotId);
            snapshotId = vm.snapshot();

            _testShouldSupplyMarketP2PAndOnPool(activeMarkets[marketIndex], _amount);
        }
    }

    function testShouldNotSupplyZeroAmount() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
            user.supply(market.poolToken, address(user), 0);
        }
    }

    function testShouldNotSupplyOnBehalfAddressZero(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(PositionsManagerUtils.AddressIsZero.selector);
            user.supply(market.poolToken, address(0), _amount);
        }
    }
}
