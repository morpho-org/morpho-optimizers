// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRepay is TestSetup {
    using CompoundMath for uint256;

    struct RepayTest {
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
        uint256 borrowedAmount;
        uint256 collateralAmount;
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

    function _setUpRepayTest(
        address _borrowedPoolToken,
        address _collateralPoolToken,
        uint96 _amount
    ) internal returns (RepayTest memory test) {
        test.borrowedPoolToken = ICToken(_borrowedPoolToken);
        test.collateralPoolToken = ICToken(_collateralPoolToken);

        (, test.collateralFactor, ) = morpho.comptroller().markets(
            address(test.collateralPoolToken)
        );
        test.borrowCap = morpho.comptroller().borrowCaps(address(test.borrowedPoolToken));

        (test.collateral, test.collateralDecimals) = _getUnderlying(_collateralPoolToken);
        (test.borrowed, test.borrowedDecimals) = _getUnderlying(_borrowedPoolToken);

        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());
        test.collateralPrice = oracle.getUnderlyingPrice(address(test.collateralPoolToken));
        test.borrowedPrice = oracle.getUnderlyingPrice(address(test.borrowedPoolToken));

        test.borrowedBalanceBefore = test.borrowed.balanceOf(address(borrower1));
        test.morphoBalanceOnPoolBefore = test.borrowedPoolToken.balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = test.borrowed.balanceOf(address(morpho));

        test.borrowedAmount = _boundBorrowedAmount(
            _amount,
            _borrowedPoolToken,
            address(test.borrowed),
            test.borrowedDecimals
        );
    }

    function _testShouldRepayMarketP2PAndFromPool(
        address _borrowedPoolToken,
        address _collateralPoolToken,
        uint96 _amount
    ) internal {
        RepayTest memory test = _setUpRepayTest(_borrowedPoolToken, _collateralPoolToken, _amount);

        test.collateralAmount =
            _getMinimumCollateralAmount(
                test.borrowedAmount,
                test.borrowedPrice,
                test.collateralPrice,
                test.collateralFactor
            ) +
            1e12; // Inflate collateral amount to compensate for compound rounding errors.
        _tip(address(test.collateral), address(borrower1), test.collateralAmount);

        borrower1.approve(address(test.collateral), test.collateralAmount);
        borrower1.supply(address(test.collateralPoolToken), test.collateralAmount);
        borrower1.borrow(address(test.borrowedPoolToken), test.borrowedAmount);

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

        vm.roll(block.number + 5_000);

        morpho.updateP2PIndexes(address(test.borrowedPoolToken));

        vm.roll(block.number + 5_000);

        assertEq(
            test.borrowed.balanceOf(address(borrower1)),
            test.borrowedAmount,
            "unexpected borrowed balance before repay"
        );

        (test.borrowedOnPoolAfter, test.borrowedInP2PAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.borrowedPoolToken), address(borrower1));

        assertGe(
            test.totalBorrowedAfter,
            test.totalBorrowedBefore,
            "unexpected borrowed amount before repay"
        );

        _tip(
            address(test.borrowed),
            address(borrower1),
            test.totalBorrowedAfter - test.totalBorrowedBefore
        );
        borrower1.approve(address(test.borrowed), type(uint256).max);
        borrower1.repay(address(test.borrowedPoolToken), type(uint256).max);

        assertApproxEqAbs(
            test.borrowed.balanceOf(address(borrower1)),
            0,
            10**(test.borrowedDecimals / 2),
            "unexpected borrowed balance after repay"
        );

        (test.borrowedOnPoolAfter, test.borrowedInP2PAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(address(test.borrowedPoolToken), address(borrower1));

        assertEq(test.borrowedOnPoolAfter, 0, "unexpected pool borrowed amount after repay");
        assertEq(test.borrowedInP2PAfter, 0, "unexpected p2p borrowed amount after repay");
        assertEq(test.totalBorrowedAfter, 0, "unexpected total borrowed after repay");
    }

    function testShouldRepayAmountP2PAndFromPool(
        uint8 _borrowMarketIndex,
        uint8 _collateralMarketIndex,
        uint96 _amount
    ) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();
        address[] memory activeCollateralMarkets = getAllFullyActiveCollateralMarkets();

        _borrowMarketIndex = uint8(_borrowMarketIndex % activeMarkets.length);
        _collateralMarketIndex = uint8(_collateralMarketIndex % activeCollateralMarkets.length);

        _testShouldRepayMarketP2PAndFromPool(
            activeMarkets[_borrowMarketIndex],
            activeCollateralMarkets[_collateralMarketIndex],
            _amount
        );
    }

    function testShouldNotRepayZeroAmount() public {
        address[] memory markets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            RepayTest memory test;
            test.borrowedPoolToken = ICToken(markets[marketIndex]);

            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            borrower1.repay(address(test.borrowedPoolToken), 0);
        }
    }
}
