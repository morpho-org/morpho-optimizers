// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRepay is TestSetup {
    using WadRayMath for uint256;

    struct RepayTest {
        TestMarket collateralMarket;
        TestMarket borrowedMarket;
        //
        uint256 collateralPrice;
        uint256 borrowedPrice;
        //
        uint256 borrowedAmount;
        uint256 collateralAmount;
        //
        uint256 p2pBorrowIndex;
        uint256 poolBorrowIndex;
        //
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        //
        uint256 borrowedOnPoolBefore;
        uint256 borrowedInP2PBefore;
        uint256 totalBorrowedBefore;
        //
        uint256 borrowedOnPoolAfter;
        uint256 borrowedInP2PAfter;
        uint256 totalBorrowedAfter;
    }

    function _setUpRepayTest(
        TestMarket memory _collateralMarket,
        TestMarket memory _borrowedMarket,
        uint96 _amount
    ) internal returns (RepayTest memory test) {
        test.collateralMarket = _collateralMarket;
        test.borrowedMarket = _borrowedMarket;

        test.collateralPrice = oracle.getAssetPrice(_collateralMarket.underlying);
        test.borrowedPrice = oracle.getAssetPrice(_borrowedMarket.underlying);

        test.borrowedAmount = _boundBorrowedAmount(_borrowedMarket, _amount, test.borrowedPrice);
        test.collateralAmount = _getMinimumCollateralAmount(
            test.borrowedAmount,
            test.borrowedPrice,
            _borrowedMarket.decimals,
            test.collateralPrice,
            _collateralMarket.decimals,
            _collateralMarket.ltv
        ).wadMul(1.0001 ether);

        if (test.collateralAmount > 0) {
            _tip(_collateralMarket.underlying, address(user), test.collateralAmount);

            user.approve(_collateralMarket.underlying, test.collateralAmount);
            user.supply(_collateralMarket.poolToken, address(user), test.collateralAmount);
        }

        user.borrow(_borrowedMarket.poolToken, test.borrowedAmount);

        vm.roll(block.number + 100_000);
        vm.warp(block.timestamp + 2 weeks);

        morpho.updateIndexes(_borrowedMarket.poolToken);

        test.p2pBorrowIndex = morpho.p2pBorrowIndex(_borrowedMarket.poolToken);
        (, , test.poolBorrowIndex) = morpho.poolIndexes(_borrowedMarket.poolToken);
    }

    function _testShouldRepayMarketP2PAndFromPool(
        TestMarket memory _collateralMarket,
        TestMarket memory _borrowedMarket,
        uint96 _amount
    ) internal returns (RepayTest memory test) {
        test = _setUpRepayTest(_collateralMarket, _borrowedMarket, _amount);

        (test.balanceInP2P, test.balanceOnPool) = morpho.borrowBalanceInOf(
            _borrowedMarket.poolToken,
            address(user)
        );

        test.borrowedInP2PBefore = test.balanceInP2P.rayMul(test.p2pBorrowIndex);
        test.borrowedOnPoolBefore = test.balanceOnPool.rayMul(test.poolBorrowIndex);
        test.totalBorrowedBefore = test.borrowedOnPoolBefore + test.borrowedInP2PBefore;

        _tip(
            _borrowedMarket.underlying,
            address(user),
            test.totalBorrowedBefore - ERC20(_borrowedMarket.underlying).balanceOf(address(user))
        );
        user.approve(_borrowedMarket.underlying, type(uint256).max);
        user.repay(_borrowedMarket.poolToken, address(user), type(uint256).max);

        assertApproxEqAbs(
            ERC20(_borrowedMarket.underlying).balanceOf(address(user)),
            0,
            10**(_borrowedMarket.decimals / 2),
            "unexpected borrowed balance after repay"
        );

        (test.borrowedInP2PAfter, test.borrowedOnPoolAfter, test.totalBorrowedAfter) = lens
        .getCurrentBorrowBalanceInOf(_borrowedMarket.poolToken, address(user));

        assertEq(test.borrowedOnPoolAfter, 0, "unexpected pool borrowed amount after repay");
        assertEq(test.borrowedInP2PAfter, 0, "unexpected p2p borrowed amount after repay");
        assertEq(test.totalBorrowedAfter, 0, "unexpected total borrowed after repay");
    }

    function testShouldRepayAmountP2PAndFromPool(uint96 _amount) public {
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
                if (snapshotId < type(uint256).max) vm.revertTo(snapshotId);
                snapshotId = vm.snapshot();

                _testShouldRepayMarketP2PAndFromPool(
                    collateralMarkets[collateralMarketIndex],
                    borrowableMarkets[borrowedMarketIndex],
                    _amount
                );
            }
        }
    }

    function testShouldNotRepayZeroAmount() public {
        for (uint256 marketIndex; marketIndex < unpausedMarkets.length; ++marketIndex) {
            TestMarket memory market = unpausedMarkets[marketIndex];

            vm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
            user.repay(market.poolToken, address(user), 0);
        }
    }
}
