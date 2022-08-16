// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

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
        uint256 borrowCap;
        uint256 collateralFactor;
        uint256 collateralPrice;
        uint256 borrowedPrice;
        uint256 borrowedBalanceBefore;
        uint256 borrowedBalanceAfter;
        uint256 morphoBalanceOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        uint256 p2pBorrowIndex;
        uint256 poolBorrowIndex;
        uint256 borrowRatePerBlock;
        uint256 p2pBorrowRatePerBlock;
        uint256 poolBorrowRatePerBlock;
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        uint256 unclaimedRewardsBefore;
        uint256 unclaimedRewardsAfter;
        uint256 borrowedOnPoolBefore;
        uint256 borrowedInP2PBefore;
        uint256 totalBorrowedBefore;
        uint256 borrowedOnPoolAfter;
        uint256 borrowedInP2PAfter;
        uint256 totalBorrowedAfter;
    }

    function testShouldBorrowAmountP2PAndFromPool(
        uint8 collateralMarketIndex,
        uint8 borrowMarketIndex,
        uint256 amount
    ) public {
        address[] memory markets = lens.getAllMarkets();

        borrowMarketIndex = uint8(borrowMarketIndex % markets.length);
        collateralMarketIndex = uint8(collateralMarketIndex % markets.length);

        BorrowTest memory test;
        test.collateralPoolToken = ICToken(markets[collateralMarketIndex]);
        test.borrowedPoolToken = ICToken(markets[borrowMarketIndex]);

        (, test.collateralFactor, ) = morpho.comptroller().markets(
            address(test.collateralPoolToken)
        );
        vm.assume(test.collateralFactor > 0);
        test.borrowCap = morpho.comptroller().borrowCaps(address(test.borrowedPoolToken));

        test.collateral = ERC20(
            address(test.collateralPoolToken) == morpho.cEth()
                ? morpho.wEth()
                : test.collateralPoolToken.underlying()
        );
        test.collateralDecimals = test.collateral.decimals();
        test.borrowed = ERC20(
            address(test.borrowedPoolToken) == morpho.cEth()
                ? morpho.wEth()
                : test.borrowedPoolToken.underlying()
        );
        test.borrowedDecimals = test.borrowed.decimals();

        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        test.collateralPrice = oracle.getUnderlyingPrice(address(test.collateralPoolToken));
        test.borrowedPrice = oracle.getUnderlyingPrice(address(test.borrowedPoolToken));

        test.borrowedBalanceBefore = test.borrowed.balanceOf(address(borrower1));
        test.morphoBalanceOnPoolBefore = test.borrowedPoolToken.balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = test.borrowed.balanceOf(address(morpho));

        amount = bound(
            amount,
            10**(test.borrowedDecimals - 6),
            Math.min(
                (test.borrowCap > 0 ? test.borrowCap - 1 : type(uint256).max) -
                    test.borrowedPoolToken.totalBorrows(),
                address(test.borrowed) == wEth
                    ? address(test.borrowedPoolToken).balance
                    : test.borrowed.balanceOf(address(test.borrowedPoolToken))
            )
        );

        uint256 collateralAmount = amount.mul(test.borrowedPrice).div(test.collateralFactor).div(
            test.collateralPrice
        ) + 1e12; // Inflate collateral amount to compensate for compound rounding errors.
        if (address(test.collateral) == wEth) hoax(wEth, collateralAmount);
        deal(address(test.collateral), address(borrower1), collateralAmount);

        borrower1.approve(address(test.collateral), collateralAmount);
        borrower1.supply(address(test.collateralPoolToken), collateralAmount);
        borrower1.borrow(address(test.borrowedPoolToken), amount);

        test.borrowedBalanceAfter = test.borrowed.balanceOf(address(borrower1));
        test.p2pBorrowIndex = morpho.p2pBorrowIndex(address(test.borrowedPoolToken));
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

        address[] memory borrowedPoolTokens = new address[](1);
        borrowedPoolTokens[0] = address(test.borrowedPoolToken);
        test.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(
            borrowedPoolTokens,
            address(borrower1)
        );

        test.borrowedInP2PBefore = test.balanceInP2P.mul(test.p2pBorrowIndex);
        test.borrowedOnPoolBefore = test.balanceOnPool.mul(test.poolBorrowIndex);
        test.totalBorrowedBefore = test.borrowedOnPoolBefore + test.borrowedInP2PBefore;

        assertEq(
            test.collateral.balanceOf(address(borrower1)),
            address(test.collateral) == address(test.borrowed) ? amount : 0,
            "unexpected collateral balance after"
        );
        assertEq(
            test.borrowedBalanceAfter,
            test.borrowedBalanceBefore + amount,
            "unexpected borrowed balance change"
        );
        assertLe(
            test.borrowedOnPoolBefore + test.borrowedInP2PBefore,
            amount,
            "greater borrowed amount than expected"
        );
        assertGe(
            test.borrowedOnPoolBefore + test.borrowedInP2PBefore + 10**(test.borrowedDecimals / 2),
            amount,
            "unexpected borrowed amount"
        );
        if (morpho.p2pDisabled(address(test.borrowedPoolToken)))
            assertEq(test.borrowedInP2PBefore, 0, "unexpected underlying balance p2p");
        assertEq(test.unclaimedRewardsBefore, 0, "unclaimed rewards not zero");

        // assertEq( // TODO: check borrow delta
        //     test.borrowed.balanceOf(address(morpho)),
        //     test.morphoUnderlyingBalanceBefore,
        //     "unexpected morpho underlying balance"
        // );
        // assertEq(
        //     test.morphoBalanceOnPoolBefore - test.borrowedPoolToken.balanceOf(address(morpho)),
        //     test.balanceOnPool,
        //     "unexpected morpho underlying balance on pool"
        // );

        vm.roll(block.number + 500);

        morpho.updateP2PIndexes(address(test.borrowedPoolToken));

        vm.roll(block.number + 500);

        test.unclaimedRewardsAfter = lens.getUserUnclaimedRewards(
            borrowedPoolTokens,
            address(borrower1)
        );
        (test.borrowedOnPoolAfter, test.borrowedInP2PAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.borrowedPoolToken), address(borrower1));

        for (uint256 i; i < 1_000; ++i) {
            test.totalBorrowedBefore = test.totalBorrowedBefore.mul(1e18 + test.borrowRatePerBlock);
            test.borrowedOnPoolBefore = test.borrowedOnPoolBefore.mul(
                1e18 + test.poolBorrowRatePerBlock
            );
            test.borrowedInP2PBefore = test.borrowedInP2PBefore.mul(
                1e18 + test.p2pBorrowRatePerBlock
            );
        }

        assertApproxEqAbs(
            test.borrowedOnPoolBefore,
            test.borrowedOnPoolAfter,
            test.borrowedOnPoolBefore / 1e3 + 1,
            "unexpected pool borrowed amount"
        );
        assertApproxEqAbs(
            test.borrowedInP2PBefore,
            test.borrowedInP2PAfter,
            test.borrowedInP2PBefore / 1e3 + 1,
            "unexpected p2p borrowed amount"
        );
        assertApproxEqAbs(
            test.totalBorrowedBefore,
            test.totalBorrowedAfter,
            test.totalBorrowedBefore / 1e3 + 1,
            "unexpected total borrowed amount from avg borrow rate"
        );
        assertApproxEqAbs(
            test.borrowedInP2PBefore + test.borrowedOnPoolBefore,
            test.totalBorrowedAfter,
            test.totalBorrowedBefore / 1e3 + 1,
            "unexpected total borrowed amount"
        );
        if (
            test.borrowedOnPoolAfter > 0 &&
            morpho.comptroller().compBorrowSpeeds(address(test.borrowedPoolToken)) > 0
        )
            assertGt(
                test.unclaimedRewardsAfter,
                test.unclaimedRewardsBefore,
                "lower unclaimed rewards"
            );
    }

    function testShouldNotBorrowZeroAmount(uint8 marketIndex) public {
        address[] memory markets = lens.getAllMarkets();

        vm.assume(marketIndex < markets.length);

        BorrowTest memory test;
        test.borrowedPoolToken = ICToken(markets[marketIndex]);

        vm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        borrower1.borrow(address(test.borrowedPoolToken), 0);
    }

    function testShouldNotBorrowWithoutEnoughCollateral(
        uint8 collateralMarketIndex,
        uint8 borrowMarketIndex,
        uint256 amount
    ) public {
        address[] memory markets = lens.getAllMarkets();

        borrowMarketIndex = uint8(borrowMarketIndex % markets.length);
        collateralMarketIndex = uint8(collateralMarketIndex % markets.length);

        BorrowTest memory test;
        test.collateralPoolToken = ICToken(markets[collateralMarketIndex]);
        test.borrowedPoolToken = ICToken(markets[borrowMarketIndex]);

        (, test.collateralFactor, ) = morpho.comptroller().markets(
            address(test.collateralPoolToken)
        );
        test.borrowCap = morpho.comptroller().borrowCaps(address(test.borrowedPoolToken));

        test.collateral = ERC20(
            address(test.collateralPoolToken) == morpho.cEth()
                ? morpho.wEth()
                : test.collateralPoolToken.underlying()
        );
        test.collateralDecimals = test.collateral.decimals();
        test.borrowed = ERC20(
            address(test.borrowedPoolToken) == morpho.cEth()
                ? morpho.wEth()
                : test.borrowedPoolToken.underlying()
        );
        test.borrowedDecimals = test.borrowed.decimals();

        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        test.collateralPrice = oracle.getUnderlyingPrice(address(test.collateralPoolToken));
        test.borrowedPrice = oracle.getUnderlyingPrice(address(test.borrowedPoolToken));

        test.borrowedBalanceBefore = test.borrowed.balanceOf(address(borrower1));
        test.morphoBalanceOnPoolBefore = test.borrowedPoolToken.balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = test.borrowed.balanceOf(address(morpho));

        amount = bound(
            amount,
            10**(test.borrowedDecimals - 6),
            Math.min(
                (test.borrowCap > 0 ? test.borrowCap - 1 : type(uint256).max) -
                    test.borrowedPoolToken.totalBorrows(),
                address(test.borrowed) == wEth
                    ? address(test.borrowedPoolToken).balance
                    : test.borrowed.balanceOf(address(test.borrowedPoolToken))
            )
        );

        if (test.collateralFactor > 0) {
            uint256 collateralAmount = amount
            .mul(test.borrowedPrice)
            .div(test.collateralFactor)
            .div(test.collateralPrice); // Not enough collateral because of compound rounding errors.
            if (address(test.collateral) == wEth) hoax(wEth, collateralAmount);
            deal(address(test.collateral), address(borrower1), collateralAmount);

            if (collateralAmount > 0) {
                borrower1.approve(address(test.collateral), collateralAmount);
                borrower1.supply(address(test.collateralPoolToken), collateralAmount);
            }
        }

        vm.expectRevert(PositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(address(test.borrowedPoolToken), amount);
    }
}
