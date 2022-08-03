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
        uint256 totalUnderlyingBefore;
        uint256 borrowedOnPoolAfter;
        uint256 borrowedInP2PAfter;
        uint256 totalUnderlyingAfter;
    }

    function testShouldBorrowAmountP2PAndFromPool(uint8 marketIndex, uint256 amount) public {
        address[] memory markets = lens.getAllMarkets();

        marketIndex = uint8(marketIndex % markets.length);

        BorrowTest memory test;
        test.collateral = ERC20(wEth);
        test.collateralPoolToken = ICToken(cEth);
        test.collateralDecimals = test.collateral.decimals();
        test.borrowedPoolToken = ICToken(markets[marketIndex]);
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

        uint256 collateralBalance = test.collateral.balanceOf(address(borrower1));

        amount = bound(
            amount,
            10**(test.borrowedDecimals - 3),
            Math.min(
                morpho.comptroller().borrowCaps(address(test.borrowedPoolToken)),
                Math.min(
                    collateralBalance.mul(test.collateralPrice).div(test.borrowedPrice),
                    test.borrowedBalanceBefore
                )
            )
        );

        test.morphoBalanceOnPoolBefore = test.borrowedPoolToken.balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = test.borrowed.balanceOf(address(morpho));

        borrower1.approve(address(test.collateral), type(uint256).max);
        borrower1.supply(address(test.collateralPoolToken), collateralBalance);
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
        test.totalUnderlyingBefore = test.borrowedOnPoolBefore + test.borrowedInP2PBefore;

        assertEq(
            test.borrowedBalanceAfter - test.borrowedBalanceBefore,
            amount,
            "unexpected underlying balance change"
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
        (test.borrowedOnPoolAfter, test.borrowedInP2PAfter, test.totalUnderlyingAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.borrowedPoolToken), address(borrower1));

        for (uint256 i; i < 1_000; ++i) {
            test.totalUnderlyingBefore = test.totalUnderlyingBefore.mul(
                1e18 + test.borrowRatePerBlock
            );
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
            test.borrowedOnPoolBefore / 1e3,
            "unexpected pool underlying amount"
        );
        assertApproxEqAbs(
            test.borrowedInP2PBefore,
            test.borrowedInP2PAfter,
            test.borrowedInP2PBefore / 1e3,
            "unexpected p2p underlying amount"
        );
        assertApproxEqAbs(
            test.totalUnderlyingBefore,
            test.totalUnderlyingAfter,
            test.totalUnderlyingBefore / 1e3,
            "unexpected total underlying amount from avg borrow rate"
        );
        assertApproxEqAbs(
            test.borrowedInP2PBefore + test.borrowedOnPoolBefore,
            test.totalUnderlyingAfter,
            test.totalUnderlyingBefore / 1e3,
            "unexpected total underlying amount"
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

    // function testShouldNotBorrowWithoutEnoughCollateral(
    //     uint8 collateralIndex,
    //     uint8 borrowedIndex,
    //     uint128 collateralAmount,
    //     uint128 borrowedAmount
    // ) public {
    //     address[] memory markets = lens.getAllMarkets();

    //     vm.assume(collateralIndex < markets.length);
    //     vm.assume(borrowedIndex < markets.length);

    //     BorrowTest memory test;
    //     test.borrowedPoolToken = ICToken(markets[marketIndex]);

    //     vm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
    //     borrower1.borrow(address(test.borrowedPoolToken), 0);
    // }
}
