// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    using CompoundMath for uint256;

    struct BorrowTest {
        TestMarket collateralMarket;
        TestMarket borrowedMarket;
        //
        uint256 collateralPrice;
        uint256 borrowedPrice;
        //
        uint256 borrowedAmount;
        uint256 collateralAmount;
        //
        uint256 borrowedBalanceBefore;
        uint256 borrowedBalanceAfter;
        //
        uint256 morphoSuppliedOnPoolBefore;
        uint256 morphoBorrowedOnPoolBefore;
        uint256 morphoBorrowedBalanceBefore;
        //
        bool p2pDisabled;
        uint256 p2pSupplyDelta;
        //
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        //
        uint256 borrowRatePerBlock;
        uint256 p2pBorrowRatePerBlock;
        uint256 poolBorrowRatePerBlock;
        //
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        //
        uint256 unclaimedRewardsBefore;
        //
        uint256 borrowedOnPoolBefore;
        uint256 borrowedInP2PBefore;
        uint256 totalBorrowedBefore;
        //
        uint256 borrowedOnPoolAfter;
        uint256 borrowedInP2PAfter;
        uint256 totalBorrowedAfter;
    }

    function _setUpBorrowTest(
        TestMarket memory _collateralMarket,
        TestMarket memory _borrowedMarket,
        uint96 _amount,
        uint256 _collateralMultiplier
    ) internal returns (BorrowTest memory test) {
        test.collateralMarket = _collateralMarket;
        test.borrowedMarket = _borrowedMarket;

        test.collateralPrice = oracle.getUnderlyingPrice(_collateralMarket.poolToken);
        test.borrowedPrice = oracle.getUnderlyingPrice(_borrowedMarket.poolToken);

        test.p2pDisabled = morpho.p2pDisabled(_borrowedMarket.poolToken);

        test.borrowedAmount = _boundBorrowedAmount(_borrowedMarket, _amount, test.borrowedPrice);
        test.collateralAmount = _getMinimumCollateralAmount(
            test.borrowedAmount,
            test.borrowedPrice,
            test.collateralPrice,
            _collateralMarket.collateralFactor
        ).mul(_collateralMultiplier);

        if (test.collateralAmount > 0) {
            _tip(_collateralMarket.underlying, address(user), test.collateralAmount);

            user.approve(_collateralMarket.underlying, test.collateralAmount);
            user.supply(_collateralMarket.poolToken, address(user), test.collateralAmount);
        }

        _forward(100_000);

        morpho.updateP2PIndexes(_borrowedMarket.poolToken);

        (test.p2pSupplyDelta, , , ) = morpho.deltas(_borrowedMarket.poolToken);
        test.borrowedBalanceBefore = ERC20(_borrowedMarket.underlying).balanceOf(address(user));
        test.morphoSuppliedOnPoolBefore = ICToken(_borrowedMarket.poolToken).balanceOfUnderlying(
            address(morpho)
        );
        test.morphoBorrowedOnPoolBefore = ICToken(_borrowedMarket.poolToken).borrowBalanceCurrent(
            address(morpho)
        );
        test.morphoBorrowedBalanceBefore = ERC20(_borrowedMarket.underlying).balanceOf(
            address(morpho)
        );
    }

    function _testShouldBorrowMarketP2PAndFromPool(
        TestMarket memory _collateralMarket,
        TestMarket memory _borrowedMarket,
        uint96 _amount
    ) internal returns (BorrowTest memory test) {
        test = _setUpBorrowTest(
            _collateralMarket,
            _borrowedMarket,
            _amount,
            1.001 ether // Inflate collateral amount to compensate for rounding errors.
        );

        user.borrow(_borrowedMarket.poolToken, test.borrowedAmount);

        test.borrowedBalanceAfter = ERC20(_borrowedMarket.underlying).balanceOf(address(user));
        test.p2pBorrowIndex = morpho.p2pBorrowIndex(_borrowedMarket.poolToken);
        test.poolSupplyIndex = ICToken(_borrowedMarket.poolToken).exchangeRateCurrent();
        test.poolBorrowIndex = ICToken(_borrowedMarket.poolToken).borrowIndex();
        test.borrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            _borrowedMarket.poolToken,
            address(user)
        );
        (, test.p2pBorrowRatePerBlock, , test.poolBorrowRatePerBlock) = lens.getRatesPerBlock(
            _borrowedMarket.poolToken
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.borrowBalanceInOf(
            _borrowedMarket.poolToken,
            address(user)
        );

        test.borrowedInP2PBefore = test.balanceInP2P.mul(test.p2pBorrowIndex);
        test.borrowedOnPoolBefore = test.balanceOnPool.mul(test.poolBorrowIndex);
        test.totalBorrowedBefore = test.borrowedOnPoolBefore + test.borrowedInP2PBefore;

        assertEq(
            ERC20(_borrowedMarket.underlying).balanceOf(address(user)),
            test.borrowedAmount,
            "unexpected borrowed balance after borrow"
        );
        assertEq(
            ERC20(_collateralMarket.underlying).balanceOf(address(user)),
            _collateralMarket.underlying == _borrowedMarket.underlying ? test.borrowedAmount : 0,
            "unexpected collateral balance after"
        );
        assertEq(
            test.borrowedBalanceAfter,
            test.borrowedBalanceBefore + test.borrowedAmount,
            "unexpected borrowed balance change"
        );
        assertLe(
            test.totalBorrowedBefore,
            test.borrowedAmount,
            "greater borrowed amount than expected"
        );
        assertGe(
            test.totalBorrowedBefore + 10**(_borrowedMarket.decimals / 2),
            test.borrowedAmount,
            "unexpected borrowed amount"
        );
        if (test.p2pDisabled) assertEq(test.balanceInP2P, 0, "unexpected p2p balance");

        address[] memory borrowedPoolTokens = new address[](1);
        borrowedPoolTokens[0] = _borrowedMarket.poolToken;
        if (address(rewardsManager) != address(0)) {
            test.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(
                borrowedPoolTokens,
                address(user)
            );
        }

        assertEq(
            ERC20(_borrowedMarket.underlying).balanceOf(address(morpho)),
            test.morphoBorrowedBalanceBefore,
            "unexpected morpho underlying balance"
        );
        assertApproxEqAbs(
            ICToken(_borrowedMarket.poolToken).balanceOfUnderlying(address(morpho)) +
                test.borrowedInP2PBefore,
            test.morphoSuppliedOnPoolBefore,
            10**(_borrowedMarket.decimals / 2),
            "unexpected morpho supply balance on pool"
        );
        assertApproxEqAbs(
            ICToken(_borrowedMarket.poolToken).borrowBalanceCurrent(address(morpho)),
            test.morphoBorrowedOnPoolBefore + test.borrowedOnPoolBefore,
            10**(_borrowedMarket.decimals / 2),
            "unexpected morpho borrow balance on pool"
        );

        if (test.p2pSupplyDelta <= test.borrowedAmount.div(test.poolSupplyIndex))
            assertGe(
                test.borrowedInP2PBefore,
                test.p2pSupplyDelta.mul(test.poolSupplyIndex),
                "expected p2p supply delta minimum match"
            );
        else
            assertApproxEqAbs(
                test.borrowedInP2PBefore,
                test.borrowedAmount,
                1,
                "expected full match"
            );

        uint256 forecastBlocks = 1_000;
        _forward(forecastBlocks / 2);

        morpho.updateP2PIndexes(_borrowedMarket.poolToken);

        _forward(forecastBlocks / 2);

        (test.borrowedOnPoolAfter, test.borrowedInP2PAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(_borrowedMarket.poolToken, address(user));

        uint256 expectedBorrowedOnPoolAfter = test.borrowedOnPoolBefore.mul(
            1e18 + test.poolBorrowRatePerBlock * forecastBlocks
        );
        uint256 expectedBorrowedInP2PAfter = test.borrowedInP2PBefore.mul(
            1e18 + test.p2pBorrowRatePerBlock * forecastBlocks
        );
        uint256 expectedTotalBorrowedAfter = test.totalBorrowedBefore.mul(
            1e18 + test.borrowRatePerBlock * forecastBlocks
        );

        assertApproxEqAbs(
            test.borrowedOnPoolAfter,
            expectedBorrowedOnPoolAfter,
            test.borrowedOnPoolAfter / 1e6 + 1,
            "unexpected pool borrowed amount"
        );
        assertApproxEqAbs(
            test.borrowedInP2PAfter,
            expectedBorrowedInP2PAfter,
            test.borrowedInP2PAfter / 1e6 + 1,
            "unexpected p2p borrowed amount"
        );
        assertApproxEqAbs(
            test.totalBorrowedAfter,
            expectedTotalBorrowedAfter,
            test.totalBorrowedAfter / 1e6 + 1,
            "unexpected total borrowed amount from avg borrow rate"
        );
        assertApproxEqAbs(
            test.totalBorrowedAfter,
            expectedBorrowedOnPoolAfter + expectedBorrowedInP2PAfter,
            test.totalBorrowedAfter / 1e6 + 1,
            "unexpected total borrowed amount"
        );
        if (
            address(rewardsManager) != address(0) &&
            test.borrowedOnPoolAfter > 0 &&
            morpho.comptroller().compBorrowSpeeds(_borrowedMarket.poolToken) > 0
        )
            assertGt(
                lens.getUserUnclaimedRewards(borrowedPoolTokens, address(user)),
                test.unclaimedRewardsBefore,
                "lower unclaimed rewards"
            );
    }

    function testShouldBorrowAmountP2PAndFromPool(uint96 _amount) public {
        for (
            uint256 collateralMarketIndex;
            collateralMarketIndex < collateralMarkets.length;
            ++collateralMarketIndex
        ) {
            for (
                uint256 borrowedMarketIndex;
                borrowedMarketIndex < borrowableMarkets.length;
                ++borrowedMarketIndex
            ) {
                _revert();

                _testShouldBorrowMarketP2PAndFromPool(
                    collateralMarkets[collateralMarketIndex],
                    borrowableMarkets[borrowedMarketIndex],
                    _amount
                );
            }
        }
    }

    function testShouldNotBorrowZeroAmount() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            user.borrow(market.poolToken, 0);
        }
    }

    function testShouldNotBorrowWithoutEnoughCollateral(uint96 _amount) public {
        for (
            uint256 collateralMarketIndex;
            collateralMarketIndex < collateralMarkets.length;
            ++collateralMarketIndex
        ) {
            for (
                uint256 borrowedMarketIndex;
                borrowedMarketIndex < borrowableMarkets.length;
                ++borrowedMarketIndex
            ) {
                _revert();

                BorrowTest memory test = _setUpBorrowTest(
                    collateralMarkets[collateralMarketIndex],
                    borrowableMarkets[borrowedMarketIndex],
                    _amount,
                    0.995 ether
                );

                vm.expectRevert(PositionsManager.UnauthorisedBorrow.selector);
                user.borrow(test.borrowedMarket.poolToken, test.borrowedAmount);
            }
        }
    }
}
