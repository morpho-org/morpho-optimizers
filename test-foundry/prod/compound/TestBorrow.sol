// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    using CompoundMath for uint256;

    struct BorrowTest {
        ERC20 underlying;
        ICToken poolToken;
        uint256 decimals;
        uint256 wEthPrice;
        uint256 underlyingPrice;
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
        uint256 underlyingOnPoolBefore;
        uint256 underlyingInP2PBefore;
        uint256 totalUnderlyingBefore;
        uint256 underlyingOnPoolAfter;
        uint256 underlyingInP2PAfter;
        uint256 totalUnderlyingAfter;
    }

    function testShouldBorrowAmountP2PAndFromPool(uint8 marketIndex, uint256 amount) public {
        address[] memory markets = lens.getAllMarkets();

        vm.assume(marketIndex < markets.length);

        BorrowTest memory test;
        test.poolToken = ICToken(markets[marketIndex]);
        test.underlying = ERC20(
            address(test.poolToken) == morpho.cEth() ? morpho.wEth() : test.poolToken.underlying()
        );
        test.decimals = test.underlying.decimals();

        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        test.wEthPrice = oracle.getUnderlyingPrice(cEth);
        test.underlyingPrice = oracle.getUnderlyingPrice(address(test.poolToken));

        uint256 wEthBalance = ERC20(wEth).balanceOf(address(borrower1));

        vm.assume(
            amount >= 10**(test.decimals - 3) &&
                amount <=
                Math.min(
                    morpho.comptroller().borrowCaps(address(test.poolToken)),
                    Math.min(
                        wEthBalance.mul(test.wEthPrice).div(test.underlyingPrice),
                        test.underlying.balanceOf(address(test.poolToken))
                    )
                )
        );

        test.morphoBalanceOnPoolBefore = test.poolToken.balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = test.underlying.balanceOf(address(morpho));

        borrower1.approve(wEth, type(uint256).max);
        borrower1.supply(cEth, wEthBalance);
        borrower1.borrow(address(test.poolToken), amount);

        test.p2pBorrowIndex = morpho.p2pBorrowIndex(address(test.poolToken));
        test.poolBorrowIndex = test.poolToken.borrowIndex();
        test.borrowRatePerBlock = lens.getCurrentUserBorrowRatePerBlock(
            address(test.poolToken),
            address(borrower1)
        );
        (, test.p2pBorrowRatePerBlock, , test.poolBorrowRatePerBlock) = lens.getRatesPerBlock(
            address(test.poolToken)
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.borrowBalanceInOf(
            address(test.poolToken),
            address(borrower1)
        );

        address[] memory poolTokens = new address[](1);
        poolTokens[0] = address(test.poolToken);
        test.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(poolTokens, address(borrower1));

        test.underlyingInP2PBefore = test.balanceInP2P.mul(test.p2pBorrowIndex);
        test.underlyingOnPoolBefore = test.balanceOnPool.mul(test.poolBorrowIndex);
        test.totalUnderlyingBefore = test.underlyingOnPoolBefore + test.underlyingInP2PBefore;

        assertLe(
            test.underlyingOnPoolBefore + test.underlyingInP2PBefore,
            amount,
            "greater borrowed amount than expected"
        );
        assertGe(
            test.underlyingOnPoolBefore + test.underlyingInP2PBefore + 10**(test.decimals / 2),
            amount,
            "unexpected borrowed amount"
        );
        if (morpho.p2pDisabled(address(test.poolToken)))
            assertEq(test.underlyingInP2PBefore, 0, "unexpected underlying balance p2p");
        assertEq(test.unclaimedRewardsBefore, 0, "unclaimed rewards not zero");

        // assertEq( // TODO: check borrow delta
        //     test.underlying.balanceOf(address(morpho)),
        //     test.morphoUnderlyingBalanceBefore,
        //     "unexpected morpho underlying balance"
        // );
        // assertEq(
        //     test.morphoBalanceOnPoolBefore - test.poolToken.balanceOf(address(morpho)),
        //     test.balanceOnPool,
        //     "unexpected morpho underlying balance on pool"
        // );

        vm.roll(block.number + 500);

        morpho.updateP2PIndexes(address(test.poolToken));

        vm.roll(block.number + 500);

        test.unclaimedRewardsAfter = lens.getUserUnclaimedRewards(poolTokens, address(borrower1));
        (test.underlyingOnPoolAfter, test.underlyingInP2PAfter, test.totalUnderlyingAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.poolToken), address(borrower1));

        for (uint256 i; i < 1_000; ++i) {
            test.totalUnderlyingBefore = test.totalUnderlyingBefore.mul(
                1e18 + test.borrowRatePerBlock
            );
            test.underlyingOnPoolBefore = test.underlyingOnPoolBefore.mul(
                1e18 + test.poolBorrowRatePerBlock
            );
            test.underlyingInP2PBefore = test.underlyingInP2PBefore.mul(
                1e18 + test.p2pBorrowRatePerBlock
            );
        }

        assertApproxEqAbs(
            test.underlyingOnPoolBefore,
            test.underlyingOnPoolAfter,
            test.underlyingOnPoolBefore / 1e3,
            "unexpected pool underlying amount"
        );
        assertApproxEqAbs(
            test.underlyingInP2PBefore,
            test.underlyingInP2PAfter,
            test.underlyingInP2PBefore / 1e3,
            "unexpected p2p underlying amount"
        );
        assertApproxEqAbs(
            test.totalUnderlyingBefore,
            test.totalUnderlyingAfter,
            test.totalUnderlyingBefore / 1e3,
            "unexpected total underlying amount from avg borrow rate"
        );
        assertApproxEqAbs(
            test.underlyingInP2PBefore + test.underlyingOnPoolBefore,
            test.totalUnderlyingAfter,
            test.totalUnderlyingBefore / 1e3,
            "unexpected total underlying amount"
        );
        if (
            test.underlyingOnPoolAfter > 0 &&
            morpho.comptroller().compBorrowSpeeds(address(test.poolToken)) > 0
        )
            assertGt(
                test.unclaimedRewardsAfter,
                test.unclaimedRewardsBefore,
                "lower unclaimed rewards"
            );
    }
}
