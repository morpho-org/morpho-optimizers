// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    using CompoundMath for uint256;

    struct BorrowTest {
        ERC20 collateral;
        ICToken collateralPoolToken;
        uint256 collateralDecimals;
        ERC20 borrowed;
        ICToken borrowedPoolToken;
        uint256 borrowedDecimals;
        uint256 collateralFactor;
        uint256 collateralPrice;
        uint256 borrowedPrice;
        uint256 borrowedAmount;
        uint256 collateralAmount;
        uint256 borrowedBalanceBefore;
        uint256 borrowedBalanceAfter;
        uint256 morphoBorrowedOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        bool p2pDisabled;
        uint256 p2pSupplyDelta;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        uint256 borrowRatePerBlock;
        uint256 p2pBorrowRatePerBlock;
        uint256 poolBorrowRatePerBlock;
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        uint256 unclaimedRewardsBefore;
        uint256 borrowedOnPoolBefore;
        uint256 borrowedInP2PBefore;
        uint256 totalBorrowedBefore;
        uint256 borrowedOnPoolAfter;
        uint256 borrowedInP2PAfter;
        uint256 totalBorrowedAfter;
    }

    function _setUpBorrowTest(
        address _borrowedPoolToken,
        address _collateralPoolToken,
        uint96 _amount
    ) internal returns (BorrowTest memory test) {
        test.borrowedPoolToken = ICToken(_borrowedPoolToken);
        test.collateralPoolToken = ICToken(_collateralPoolToken);

        (, test.collateralFactor, ) = morpho.comptroller().markets(
            address(test.collateralPoolToken)
        );

        (test.collateral, test.collateralDecimals) = _getUnderlying(_collateralPoolToken);
        (test.borrowed, test.borrowedDecimals) = _getUnderlying(_borrowedPoolToken);

        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        test.collateralPrice = oracle.getUnderlyingPrice(address(test.collateralPoolToken));
        test.borrowedPrice = oracle.getUnderlyingPrice(address(test.borrowedPoolToken));

        (test.p2pSupplyDelta, , , ) = morpho.deltas(address(test.borrowedPoolToken));
        test.p2pDisabled = morpho.p2pDisabled(address(test.borrowedPoolToken));
        test.borrowedBalanceBefore = test.borrowed.balanceOf(address(borrower1));
        test.morphoBorrowedOnPoolBefore = test.borrowedPoolToken.borrowBalanceCurrent(
            address(morpho)
        );
        test.morphoUnderlyingBalanceBefore = test.borrowed.balanceOf(address(morpho));

        test.borrowedAmount = _boundBorrowedAmount(
            _amount,
            _borrowedPoolToken,
            address(test.borrowed),
            test.borrowedDecimals
        );
    }

    function _testShouldBorrowMarketP2PAndFromPool(
        address _borrowedPoolToken,
        address _collateralPoolToken,
        uint96 _amount
    ) internal {
        BorrowTest memory test = _setUpBorrowTest(
            _borrowedPoolToken,
            _collateralPoolToken,
            _amount
        );

        test.collateralAmount =
            _getMinimumCollateralAmount(
                test.borrowedAmount,
                test.borrowedPrice,
                test.collateralPrice,
                test.collateralFactor
            ) +
            10**(test.collateralDecimals - 5); // Inflate collateral amount to compensate for compound rounding errors.
        _tip(address(test.collateral), address(borrower1), test.collateralAmount);

        borrower1.approve(address(test.collateral), test.collateralAmount);
        borrower1.supply(address(test.collateralPoolToken), test.collateralAmount);
        borrower1.borrow(address(test.borrowedPoolToken), test.borrowedAmount);

        test.borrowedBalanceAfter = test.borrowed.balanceOf(address(borrower1));
        test.p2pBorrowIndex = morpho.p2pBorrowIndex(address(test.borrowedPoolToken));
        test.poolSupplyIndex = test.borrowedPoolToken.exchangeRateCurrent();
        test.poolBorrowIndex = test.borrowedPoolToken.borrowIndex();
        test.borrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            address(test.borrowedPoolToken),
            address(borrower1)
        );
        (, test.p2pBorrowRatePerBlock, , test.poolBorrowRatePerBlock) = lens.getRatesPerBlock(
            address(test.borrowedPoolToken)
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.borrowBalanceInOf(
            address(test.borrowedPoolToken),
            address(borrower1)
        );

        test.borrowedInP2PBefore = test.balanceInP2P.mul(test.p2pBorrowIndex);
        test.borrowedOnPoolBefore = test.balanceOnPool.mul(test.poolBorrowIndex);
        test.totalBorrowedBefore = test.borrowedOnPoolBefore + test.borrowedInP2PBefore;

        assertEq(
            test.collateral.balanceOf(address(borrower1)),
            address(test.collateral) == address(test.borrowed) ? test.borrowedAmount : 0,
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
            test.totalBorrowedBefore + 10**(test.borrowedDecimals / 2),
            test.borrowedAmount,
            "unexpected borrowed amount"
        );
        if (test.p2pDisabled) assertEq(test.balanceInP2P, 0, "unexpected p2p balance");

        address[] memory borrowedPoolTokens = new address[](1);
        borrowedPoolTokens[0] = address(test.borrowedPoolToken);
        if (address(rewardsManager) != address(0)) {
            test.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(
                borrowedPoolTokens,
                address(borrower1)
            );

            assertEq(test.unclaimedRewardsBefore, 0, "unclaimed rewards not zero");
        }

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

        assertEq(
            test.borrowed.balanceOf(address(morpho)),
            test.morphoUnderlyingBalanceBefore,
            "unexpected morpho underlying balance"
        );
        assertApproxEqAbs(
            test.borrowedPoolToken.borrowBalanceCurrent(address(morpho)),
            test.morphoBorrowedOnPoolBefore + test.balanceOnPool.mul(test.poolBorrowIndex),
            10,
            "unexpected morpho borrowed balance on pool"
        );

        vm.roll(block.number + 500);

        morpho.updateP2PIndexes(address(test.borrowedPoolToken));

        vm.roll(block.number + 500);

        (test.borrowedOnPoolAfter, test.borrowedInP2PAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.borrowedPoolToken), address(borrower1));

        uint256 expectedBorrowedOnPoolAfter = test.borrowedOnPoolBefore.mul(
            1e18 + test.poolBorrowRatePerBlock * 1_000
        );
        uint256 expectedBorrowedInP2PAfter = test.borrowedInP2PBefore.mul(
            1e18 + test.p2pBorrowRatePerBlock * 1_000
        );
        uint256 expectedTotalBorrowedAfter = test.totalBorrowedBefore.mul(
            1e18 + test.borrowRatePerBlock * 1_000
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
            morpho.comptroller().compBorrowSpeeds(address(test.borrowedPoolToken)) > 0
        )
            assertGt(
                lens.getUserUnclaimedRewards(borrowedPoolTokens, address(borrower1)),
                test.unclaimedRewardsBefore,
                "lower unclaimed rewards"
            );
    }

    function testShouldBorrowAmountP2PAndFromPool(
        uint8 _borrowMarketIndex,
        uint8 _collateralMarketIndex,
        uint96 _amount
    ) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();
        address[] memory activeCollateralMarkets = getAllFullyActiveCollateralMarkets();

        _borrowMarketIndex = uint8(_borrowMarketIndex % activeMarkets.length);
        _collateralMarketIndex = uint8(_collateralMarketIndex % activeCollateralMarkets.length);

        _testShouldBorrowMarketP2PAndFromPool(
            activeMarkets[_borrowMarketIndex],
            activeCollateralMarkets[_collateralMarketIndex],
            _amount
        );
    }

    function testShouldNotBorrowZeroAmount() public {
        address[] memory markets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            BorrowTest memory test;
            test.borrowedPoolToken = ICToken(markets[marketIndex]);

            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            borrower1.borrow(address(test.borrowedPoolToken), 0);
        }
    }

    function testShouldNotBorrowWithoutEnoughCollateral(
        uint8 _borrowMarketIndex,
        uint8 _collateralMarketIndex,
        uint96 _amount
    ) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();
        address[] memory activeCollateralMarkets = getAllFullyActiveCollateralMarkets();

        _borrowMarketIndex = uint8(_borrowMarketIndex % activeMarkets.length);
        _collateralMarketIndex = uint8(_collateralMarketIndex % activeCollateralMarkets.length);

        BorrowTest memory test = _setUpBorrowTest(
            activeMarkets[_borrowMarketIndex],
            activeCollateralMarkets[_collateralMarketIndex],
            _amount
        );

        if (test.collateralFactor > 0) {
            test.collateralAmount = _getMinimumCollateralAmount(
                test.borrowedAmount,
                test.borrowedPrice,
                test.collateralPrice,
                test.collateralFactor
            ); // Not enough collateral because of compound rounding errors.

            if (test.collateralAmount > 0) {
                _tip(address(test.collateral), address(borrower1), test.collateralAmount);
                borrower1.approve(address(test.collateral), test.collateralAmount);
                borrower1.supply(address(test.collateralPoolToken), test.collateralAmount);
            }
        }

        vm.expectRevert(PositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(address(test.borrowedPoolToken), test.borrowedAmount);
    }
}
