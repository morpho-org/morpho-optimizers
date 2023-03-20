// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestLifecycle is TestSetup {
    using CompoundMath for uint256;

    function _beforeSupply(MarketSideTest memory supply) internal virtual {}

    function _beforeBorrow(MarketSideTest memory borrow) internal virtual {}

    struct MorphoPosition {
        uint256 p2p;
        uint256 pool;
        uint256 total;
    }

    struct MarketSideTest {
        TestMarket market;
        uint256 amount;
        //
        bool p2pDisabled;
        uint256 p2pSupplyDelta;
        uint256 p2pBorrowDelta;
        //
        uint256 morphoPoolSupplyBefore;
        uint256 morphoPoolBorrowBefore;
        uint256 morphoUnderlyingBalanceBefore;
        //
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        //
        uint256 scaledP2PBalance;
        uint256 scaledPoolBalance;
        //
        MorphoPosition position;
        uint256 unclaimedRewardsBefore;
    }

    function _initMarketSideTest(TestMarket memory _market, uint256 _amount)
        internal
        virtual
        returns (MarketSideTest memory test)
    {
        test.market = _market;

        test.p2pDisabled = morpho.p2pDisabled(_market.poolToken);
        (test.p2pSupplyDelta, test.p2pBorrowDelta, , ) = morpho.deltas(_market.poolToken);

        test.morphoPoolSupplyBefore = ICToken(_market.poolToken).balanceOfUnderlying(
            address(morpho)
        );
        test.morphoPoolBorrowBefore = ICToken(_market.poolToken).borrowBalanceStored(
            address(morpho)
        );
        test.morphoUnderlyingBalanceBefore = ERC20(_market.underlying).balanceOf(address(morpho));

        test.amount = _amount;
    }

    function _supply(TestMarket memory _market, uint256 _amount)
        internal
        virtual
        returns (MarketSideTest memory supply)
    {
        supply = _initMarketSideTest(_market, _amount);

        _beforeSupply(supply);

        _tip(_market.underlying, address(user), supply.amount);

        user.approve(_market.underlying, supply.amount);
        user.supply(_market.poolToken, address(user), supply.amount);

        supply.p2pSupplyIndex = morpho.p2pSupplyIndex(_market.poolToken);
        supply.p2pBorrowIndex = morpho.p2pBorrowIndex(_market.poolToken);
        (, supply.poolSupplyIndex, supply.poolBorrowIndex) = morpho.lastPoolIndexes(
            _market.poolToken
        );

        (supply.scaledP2PBalance, supply.scaledPoolBalance) = morpho.supplyBalanceInOf(
            _market.poolToken,
            address(user)
        );

        supply.position.p2p = supply.scaledP2PBalance.mul(supply.p2pSupplyIndex);
        supply.position.pool = supply.scaledPoolBalance.mul(supply.poolSupplyIndex);
        supply.position.total = supply.position.p2p + supply.position.pool;
    }

    function _testSupply(MarketSideTest memory supply) internal virtual {
        assertEq(
            ERC20(supply.market.underlying).balanceOf(address(user)),
            0,
            string.concat(supply.market.symbol, " balance after supply")
        );
        assertApproxEqAbs(
            supply.position.total,
            supply.amount,
            1,
            string.concat(supply.market.symbol, " total supply")
        );
        if (supply.p2pDisabled)
            assertEq(
                supply.scaledP2PBalance,
                0,
                string.concat(supply.market.symbol, " borrow delta matched")
            );
        else {
            uint256 underlyingBorrowDelta = supply.p2pBorrowDelta.mul(supply.poolBorrowIndex);
            if (underlyingBorrowDelta <= supply.amount)
                assertGe(
                    supply.position.p2p,
                    underlyingBorrowDelta,
                    string.concat(supply.market.symbol, " borrow delta minimum match")
                );
            else
                assertApproxEqAbs(
                    supply.position.p2p,
                    supply.amount,
                    10**(supply.market.decimals / 2),
                    string.concat(supply.market.symbol, " borrow delta full match")
                );
        }

        address[] memory poolTokens = new address[](1);
        poolTokens[0] = supply.market.poolToken;
        if (address(rewardsManager) != address(0)) {
            supply.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(poolTokens, address(user));

            assertEq(
                supply.unclaimedRewardsBefore,
                0,
                string.concat(supply.market.symbol, " unclaimed rewards")
            );
        }

        assertEq(
            ERC20(supply.market.underlying).balanceOf(address(morpho)),
            supply.morphoUnderlyingBalanceBefore,
            string.concat(supply.market.symbol, " morpho balance")
        );
        assertApproxEqAbs(
            ICToken(supply.market.poolToken).balanceOfUnderlying(address(morpho)),
            supply.morphoPoolSupplyBefore + supply.position.pool,
            10,
            string.concat(supply.market.symbol, " morpho pool supply")
        );
        assertApproxEqAbs(
            ICToken(supply.market.poolToken).borrowBalanceStored(address(morpho)) +
                supply.position.p2p,
            supply.morphoPoolBorrowBefore,
            10**(supply.market.decimals / 2),
            string.concat(supply.market.symbol, " morpho pool borrow")
        );

        _forward(100_000);

        (supply.position.p2p, supply.position.pool, supply.position.total) = lens
        .getCurrentSupplyBalanceInOf(supply.market.poolToken, address(user));

        if (
            supply.position.pool > 0 &&
            address(rewardsManager) != address(0) &&
            morpho.comptroller().compSupplySpeeds(supply.market.poolToken) > 0
        )
            assertGt(
                lens.getUserUnclaimedRewards(poolTokens, address(user)),
                supply.unclaimedRewardsBefore,
                string.concat(supply.market.symbol, " unclaimed rewards after supply")
            );
    }

    function _borrow(TestMarket memory _market, uint256 _amount)
        internal
        virtual
        returns (MarketSideTest memory borrow)
    {
        borrow = _initMarketSideTest(_market, _amount);

        _beforeBorrow(borrow);

        user.borrow(_market.poolToken, borrow.amount);

        borrow.p2pSupplyIndex = morpho.p2pSupplyIndex(_market.poolToken);
        borrow.p2pBorrowIndex = morpho.p2pBorrowIndex(_market.poolToken);
        (, borrow.poolSupplyIndex, borrow.poolBorrowIndex) = morpho.lastPoolIndexes(
            _market.poolToken
        );

        (borrow.scaledP2PBalance, borrow.scaledPoolBalance) = morpho.borrowBalanceInOf(
            _market.poolToken,
            address(user)
        );

        borrow.position.p2p = borrow.scaledP2PBalance.mul(borrow.p2pBorrowIndex);
        borrow.position.pool = borrow.scaledPoolBalance.mul(borrow.poolBorrowIndex);
        borrow.position.total = borrow.position.p2p + borrow.position.pool;
    }

    function _testBorrow(MarketSideTest memory borrow) internal virtual {
        assertEq(
            ERC20(borrow.market.underlying).balanceOf(address(user)),
            borrow.amount,
            string.concat(borrow.market.symbol, " balance after borrow")
        );
        assertApproxEqAbs(
            borrow.position.total,
            borrow.amount,
            10,
            string.concat(borrow.market.symbol, " total borrow")
        );
        if (borrow.p2pDisabled)
            assertEq(
                borrow.scaledP2PBalance,
                0,
                string.concat(borrow.market.symbol, " supply delta matched")
            );
        else {
            uint256 underlyingSupplyDelta = borrow.p2pSupplyDelta.mul(borrow.poolSupplyIndex);
            if (underlyingSupplyDelta <= borrow.amount)
                assertGe(
                    borrow.position.p2p,
                    underlyingSupplyDelta,
                    string.concat(borrow.market.symbol, " supply delta minimum match")
                );
            else
                assertApproxEqAbs(
                    borrow.position.p2p,
                    borrow.amount,
                    10**(borrow.market.decimals / 2),
                    string.concat(borrow.market.symbol, " supply delta full match")
                );
        }

        address[] memory borrowedPoolTokens = new address[](1);
        borrowedPoolTokens[0] = borrow.market.poolToken;
        if (address(rewardsManager) != address(0)) {
            borrow.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(
                borrowedPoolTokens,
                address(user)
            );
        }

        assertEq(
            ERC20(borrow.market.underlying).balanceOf(address(morpho)),
            borrow.morphoUnderlyingBalanceBefore,
            string.concat(borrow.market.symbol, " morpho borrowed balance")
        );
        assertApproxEqAbs(
            ICToken(borrow.market.poolToken).balanceOfUnderlying(address(morpho)) +
                borrow.position.p2p,
            borrow.morphoPoolSupplyBefore,
            2,
            string.concat(borrow.market.symbol, " morpho borrowed pool supply")
        );
        assertApproxEqAbs(
            ICToken(borrow.market.poolToken).borrowBalanceStored(address(morpho)),
            borrow.morphoPoolBorrowBefore + borrow.position.pool,
            10**(borrow.market.decimals / 2),
            string.concat(borrow.market.symbol, " morpho borrowed pool borrow")
        );

        _forward(100_000);

        (borrow.position.p2p, borrow.position.pool, borrow.position.total) = lens
        .getCurrentBorrowBalanceInOf(borrow.market.poolToken, address(user));

        if (
            borrow.position.pool > 0 &&
            address(rewardsManager) != address(0) &&
            morpho.comptroller().compBorrowSpeeds(borrow.market.poolToken) > 0
        )
            assertGt(
                lens.getUserUnclaimedRewards(borrowedPoolTokens, address(user)),
                borrow.unclaimedRewardsBefore,
                string.concat(borrow.market.symbol, " unclaimed rewards after borrow")
            );
    }

    function _repay(MarketSideTest memory borrow) internal virtual {
        (borrow.position.p2p, borrow.position.pool, borrow.position.total) = lens
        .getCurrentBorrowBalanceInOf(borrow.market.poolToken, address(user));

        _tip(
            borrow.market.underlying,
            address(user),
            borrow.position.total - ERC20(borrow.market.underlying).balanceOf(address(user))
        );
        user.approve(borrow.market.underlying, borrow.position.total);
        user.repay(borrow.market.poolToken, address(user), type(uint256).max);

        // Sometimes, repaying all leaves 1 wei of debt.
        (, , uint256 totalBorrow) = lens.getCurrentBorrowBalanceInOf(
            borrow.market.poolToken,
            address(user)
        );
        if (totalBorrow > 0) {
            _tip(borrow.market.underlying, address(user), 1);
            user.approve(borrow.market.underlying, 1);
            user.repay(borrow.market.poolToken, address(user), 1);
        }
    }

    function _testRepay(MarketSideTest memory borrow) internal virtual {
        assertApproxEqAbs(
            ERC20(borrow.market.underlying).balanceOf(address(user)),
            0,
            10**(borrow.market.decimals / 2),
            string.concat(borrow.market.symbol, " borrow after repay")
        );

        (borrow.position.p2p, borrow.position.pool, borrow.position.total) = lens
        .getCurrentBorrowBalanceInOf(borrow.market.poolToken, address(user));

        assertEq(
            borrow.position.p2p,
            0,
            string.concat(borrow.market.symbol, " p2p borrow after repay")
        );
        assertEq(
            borrow.position.pool,
            0,
            string.concat(borrow.market.symbol, " pool borrow after repay")
        );
        assertEq(
            borrow.position.total,
            0,
            string.concat(borrow.market.symbol, " total borrow after repay")
        );
    }

    function _withdraw(MarketSideTest memory supply) internal virtual {
        (supply.position.p2p, supply.position.pool, supply.position.total) = lens
        .getCurrentSupplyBalanceInOf(supply.market.poolToken, address(user));

        user.withdraw(supply.market.poolToken, type(uint256).max);

        // Sometimes, withdrawing all leaves 1 wei of supply.
        (, , uint256 totalSupply) = lens.getCurrentSupplyBalanceInOf(
            supply.market.poolToken,
            address(user)
        );
        if (totalSupply > 0) user.withdraw(supply.market.poolToken, 1);
    }

    function _testWithdraw(MarketSideTest memory supply) internal virtual {
        assertApproxEqAbs(
            ERC20(supply.market.underlying).balanceOf(address(user)),
            supply.position.total,
            10**(supply.market.decimals / 2),
            string.concat(supply.market.symbol, " supply after withdraw")
        );

        (supply.position.p2p, supply.position.pool, supply.position.total) = lens
        .getCurrentSupplyBalanceInOf(supply.market.poolToken, address(user));

        assertEq(
            supply.position.p2p,
            0,
            string.concat(supply.market.symbol, " p2p supply after withdraw")
        );
        assertEq(
            supply.position.pool,
            0,
            string.concat(supply.market.symbol, " pool supply after withdraw")
        );
        assertEq(
            supply.position.total,
            0,
            string.concat(supply.market.symbol, " total supply after withdraw")
        );
    }

    function testShouldSupplyBorrowRepayWithdrawAllMarkets(uint96 _amount) public {
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

                uint256 borrowedPrice = oracle.getUnderlyingPrice(borrowMarket.poolToken);
                uint256 borrowAmount = _boundBorrowAmount(borrowMarket, _amount, borrowedPrice);
                uint256 supplyAmount = _getMinimumCollateralAmount(
                    borrowAmount,
                    borrowedPrice,
                    oracle.getUnderlyingPrice(supplyMarket.poolToken),
                    supplyMarket.collateralFactor
                ).mul(1.001 ether);

                MarketSideTest memory supply = _supply(supplyMarket, supplyAmount);
                _testSupply(supply);

                if (!borrowMarket.status.isBorrowPaused) {
                    MarketSideTest memory borrow = _borrow(borrowMarket, borrowAmount);
                    _testBorrow(borrow);

                    if (!borrowMarket.status.isRepayPaused) {
                        _repay(borrow);
                        _testRepay(borrow);
                    }
                }

                if (supplyMarket.status.isWithdrawPaused) continue;

                _withdraw(supply);
                _testWithdraw(supply);
            }
        }
    }

    function testShouldNotBorrowWithoutEnoughCollateral(uint96 _amount) public {
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

                if (borrowMarket.status.isBorrowPaused) continue;

                uint256 borrowAmount = _boundBorrowAmount(
                    borrowMarket,
                    _amount,
                    oracle.getUnderlyingPrice(borrowMarket.poolToken)
                );
                uint256 supplyAmount = _getMinimumCollateralAmount(
                    borrowAmount,
                    oracle.getUnderlyingPrice(borrowMarket.poolToken),
                    oracle.getUnderlyingPrice(supplyMarket.poolToken),
                    supplyMarket.collateralFactor
                ).mul(0.995 ether);

                _supply(supplyMarket, supplyAmount);

                vm.expectRevert(PositionsManager.UnauthorisedBorrow.selector);
                user.borrow(borrowMarket.poolToken, borrowAmount);
            }
        }
    }

    function testShouldNotSupplyZeroAmount() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            user.supply(activeMarkets[marketIndex].poolToken, address(user), 0);
        }
    }

    function testShouldNotSupplyOnBehalfAddressZero(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            vm.expectRevert(PositionsManager.AddressIsZero.selector);
            user.supply(activeMarkets[marketIndex].poolToken, address(0), _amount);
        }
    }

    function testShouldNotBorrowZeroAmount() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            user.borrow(activeMarkets[marketIndex].poolToken, 0);
        }
    }

    function testShouldNotRepayZeroAmount() public {
        for (uint256 marketIndex; marketIndex < unpausedMarkets.length; ++marketIndex) {
            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            user.repay(unpausedMarkets[marketIndex].poolToken, address(user), 0);
        }
    }

    function testShouldNotWithdrawZeroAmount() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            user.withdraw(activeMarkets[marketIndex].poolToken, 0);
        }
    }

    function testShouldNotWithdrawFromUnenteredMarket(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];
            if (market.status.isWithdrawPaused) continue; // isWithdrawPaused check is before user-market membership check

            vm.expectRevert(PositionsManager.UserNotMemberOfMarket.selector);
            user.withdraw(market.poolToken, _amount);
        }
    }

    function testShouldNotSupplyWhenPaused(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];
            if (!market.status.isSupplyPaused) continue;

            vm.expectRevert(PositionsManager.SupplyIsPaused.selector);
            user.supply(market.poolToken, _amount);
        }
    }

    function testShouldNotBorrowWhenPaused(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];
            if (!market.status.isBorrowPaused) continue;

            vm.expectRevert(PositionsManager.BorrowIsPaused.selector);
            user.borrow(market.poolToken, _amount);
        }
    }

    function testShouldNotRepayWhenPaused(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];
            if (!market.status.isRepayPaused) continue;

            vm.expectRevert(PositionsManager.RepayIsPaused.selector);
            user.repay(market.poolToken, type(uint256).max);
        }
    }

    function testShouldNotWithdrawWhenPaused(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];
            if (!market.status.isWithdrawPaused) continue;

            vm.expectRevert(PositionsManager.WithdrawIsPaused.selector);
            user.withdraw(market.poolToken, type(uint256).max);
        }
    }
}
