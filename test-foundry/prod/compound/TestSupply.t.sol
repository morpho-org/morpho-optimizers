// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using CompoundMath for uint256;

    struct SupplyTest {
        TestMarket market;
        uint256 morphoBalanceOnPoolBefore;
        uint256 morphoBorrowOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        bool p2pDisabled;
        uint256 p2pBorrowDelta;
        uint256 supplyRatePerBlock;
        uint256 p2pSupplyRatePerBlock;
        uint256 poolSupplyRatePerBlock;
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        uint256 unclaimedRewardsBefore;
        uint256 underlyingOnPoolBefore;
        uint256 underlyingInP2PBefore;
        uint256 totalUnderlyingBefore;
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
        test.p2pDisabled = morpho.p2pDisabled(_market.poolToken);
        test.morphoBalanceOnPoolBefore = ICToken(_market.poolToken).balanceOf(address(morpho));
        test.morphoBorrowOnPoolBefore = ICToken(_market.poolToken).borrowBalanceCurrent(
            address(morpho)
        );
        test.morphoUnderlyingBalanceBefore = ERC20(_market.underlying).balanceOf(address(morpho));

        uint256 amount = bound(_amount, 10**(_market.decimals - 6), type(uint96).max);

        _tip(_market.underlying, address(user), amount);

        user.approve(_market.underlying, amount);
        user.supply(_market.poolToken, address(user), amount);

        test.p2pSupplyIndex = morpho.p2pSupplyIndex(_market.poolToken);
        test.poolSupplyIndex = ICToken(_market.poolToken).exchangeRateCurrent();
        test.poolBorrowIndex = ICToken(_market.poolToken).borrowIndex();
        test.supplyRatePerBlock = lens.getCurrentUserSupplyRatePerBlock(
            _market.poolToken,
            address(user)
        );
        (test.p2pSupplyRatePerBlock, , test.poolSupplyRatePerBlock, ) = lens.getRatesPerBlock(
            _market.poolToken
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.supplyBalanceInOf(
            _market.poolToken,
            address(user)
        );

        test.underlyingInP2PBefore = test.balanceInP2P.mul(test.p2pSupplyIndex);
        test.underlyingOnPoolBefore = test.balanceOnPool.mul(test.poolSupplyIndex);
        test.totalUnderlyingBefore = test.underlyingOnPoolBefore + test.underlyingInP2PBefore;

        assertEq(
            ERC20(_market.underlying).balanceOf(address(user)),
            0,
            "unexpected underlying balance after"
        );
        assertLe(test.totalUnderlyingBefore, amount, "greater supplied amount than expected");
        assertGe(
            test.totalUnderlyingBefore + 10**(_market.decimals / 2),
            amount,
            "unexpected supplied amount"
        );
        if (test.p2pDisabled) assertEq(test.balanceInP2P, 0, "expected no match");

        address[] memory poolTokens = new address[](1);
        poolTokens[0] = _market.poolToken;
        if (address(rewardsManager) != address(0)) {
            test.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(poolTokens, address(user));

            assertEq(test.unclaimedRewardsBefore, 0, "unclaimed rewards not zero");
        }

        assertApproxEqAbs(
            ICToken(_market.poolToken).borrowBalanceCurrent(address(morpho)) +
                test.underlyingInP2PBefore,
            test.morphoBorrowOnPoolBefore,
            10**(_market.decimals / 2),
            "unexpected morpho borrow balance"
        );

        if (test.p2pBorrowDelta <= amount.div(test.poolBorrowIndex))
            assertGe(
                test.underlyingInP2PBefore,
                test.p2pBorrowDelta.mul(test.poolBorrowIndex),
                "expected p2p borrow delta minimum match"
            );
        else
            assertApproxEqAbs(
                test.underlyingInP2PBefore,
                amount,
                10**(_market.decimals / 2),
                "expected full match"
            );

        assertEq(
            ERC20(_market.underlying).balanceOf(address(morpho)),
            test.morphoUnderlyingBalanceBefore,
            "unexpected morpho underlying balance"
        );
        assertEq(
            ICToken(_market.poolToken).balanceOf(address(morpho)),
            test.morphoBalanceOnPoolBefore + test.balanceOnPool,
            "unexpected morpho underlying balance on pool"
        );

        vm.roll(block.number + 500);

        morpho.updateP2PIndexes(_market.poolToken);

        vm.roll(block.number + 500);

        (test.underlyingOnPoolAfter, test.underlyingInP2PAfter, test.totalUnderlyingAfter) = lens
        .getCurrentSupplyBalanceInOf(_market.poolToken, address(user));

        uint256 expectedUnderlyingOnPoolAfter = test.underlyingOnPoolBefore.mul(
            1e18 + test.poolSupplyRatePerBlock * 1_000
        );
        uint256 expectedUnderlyingInP2PAfter = test.underlyingInP2PBefore.mul(
            1e18 + test.p2pSupplyRatePerBlock * 1_000
        );
        uint256 expectedTotalUnderlyingAfter = test.totalUnderlyingBefore.mul(
            1e18 + test.supplyRatePerBlock * 1_000
        );

        assertApproxEqAbs(
            test.underlyingOnPoolAfter,
            expectedUnderlyingOnPoolAfter,
            test.underlyingOnPoolAfter / 1e9 + 1e4,
            "unexpected pool underlying amount"
        );
        assertApproxEqAbs(
            test.underlyingInP2PAfter,
            expectedUnderlyingInP2PAfter,
            test.underlyingInP2PAfter / 1e9 + 1e4,
            "unexpected p2p underlying amount"
        );
        assertApproxEqAbs(
            test.totalUnderlyingAfter,
            expectedTotalUnderlyingAfter,
            test.totalUnderlyingAfter / 1e9 + 1e4,
            "unexpected total underlying amount from avg supply rate"
        );
        assertApproxEqAbs(
            test.totalUnderlyingAfter,
            expectedUnderlyingOnPoolAfter + expectedUnderlyingInP2PAfter,
            test.totalUnderlyingBefore / 1e9 + 1e4,
            "unexpected total underlying amount"
        );
        if (
            address(rewardsManager) != address(0) &&
            test.underlyingOnPoolAfter > 0 &&
            morpho.comptroller().compSupplySpeeds(test.market.poolToken) > 0
        )
            assertGt(
                lens.getUserUnclaimedRewards(poolTokens, address(user)),
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

            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            user.supply(market.poolToken, address(user), 0);
        }
    }

    function testShouldNotSupplyOnBehalfAddressZero(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(PositionsManager.AddressIsZero.selector);
            user.supply(market.poolToken, address(0), _amount);
        }
    }
}
