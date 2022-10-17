// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestWithdraw is TestSetup {
    using CompoundMath for uint256;

    struct WithdrawTest {
        TestMarket market;
        uint256 morphoBalanceOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        uint256 underlyingOnPoolBefore;
        uint256 underlyingInP2PBefore;
        uint256 totalUnderlyingBefore;
        uint256 underlyingOnPoolAfter;
        uint256 underlyingInP2PAfter;
        uint256 totalUnderlyingAfter;
    }

    function _testShouldWithdrawMarketP2PAndOnPool(TestMarket memory _market, uint96 _amount)
        internal
    {
        WithdrawTest memory test;
        test.market = _market;

        test.morphoBalanceOnPoolBefore = ICToken(_market.poolToken).balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = ERC20(_market.underlying).balanceOf(address(morpho));

        uint256 amount = bound(_amount, 10**(_market.decimals - 4), type(uint96).max);

        _tip(_market.underlying, address(user), amount);

        user.approve(_market.underlying, amount);
        user.supply(_market.poolToken, address(user), amount);

        test.p2pSupplyIndex = morpho.p2pSupplyIndex(_market.poolToken);
        test.poolSupplyIndex = ICToken(_market.poolToken).exchangeRateCurrent();

        (test.balanceInP2P, test.balanceOnPool) = morpho.supplyBalanceInOf(
            _market.poolToken,
            address(user)
        );

        test.underlyingInP2PBefore = test.balanceInP2P.mul(test.p2pSupplyIndex);
        test.underlyingOnPoolBefore = test.balanceOnPool.mul(test.poolSupplyIndex);
        test.totalUnderlyingBefore = test.underlyingOnPoolBefore + test.underlyingInP2PBefore;

        vm.roll(block.number + 10_000);

        morpho.updateP2PIndexes(_market.poolToken);

        vm.roll(block.number + 10_000);

        assertEq(
            ERC20(_market.underlying).balanceOf(address(user)),
            0,
            "unexpected underlying balance before withdraw"
        );

        user.withdraw(_market.poolToken, test.totalUnderlyingBefore);

        (test.underlyingOnPoolAfter, test.underlyingInP2PAfter, test.totalUnderlyingAfter) = lens
        .getCurrentSupplyBalanceInOf(_market.poolToken, address(user));

        assertEq(
            ERC20(_market.underlying).balanceOf(address(user)),
            test.totalUnderlyingBefore,
            "unexpected underlying balance after withdraw"
        );

        if (test.totalUnderlyingAfter > 0) {
            user.withdraw(_market.poolToken, test.totalUnderlyingBefore); // Withdraw accrued interests.

            (
                test.underlyingOnPoolAfter,
                test.underlyingInP2PAfter,
                test.totalUnderlyingAfter
            ) = lens.getCurrentSupplyBalanceInOf(_market.poolToken, address(user));
        }

        assertEq(test.underlyingOnPoolAfter, 0, "unexpected pool underlying balance");
        assertEq(test.underlyingInP2PAfter, 0, "unexpected p2p underlying balance");
        assertEq(test.totalUnderlyingAfter, 0, "unexpected total underlying supplied");
    }

    function testShouldWithdrawAllMarketsP2PAndOnPool(uint96 _amount) public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            if (snapshotId < type(uint256).max) vm.revertTo(snapshotId);
            snapshotId = vm.snapshot();

            _testShouldWithdrawMarketP2PAndOnPool(activeMarkets[marketIndex], _amount);
        }
    }

    function testShouldNotWithdrawZeroAmount() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            user.withdraw(market.poolToken, 0);
        }
    }

    function testShouldNotWithdrawFromUnenteredMarket(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(PositionsManager.UserNotMemberOfMarket.selector);
            user.withdraw(market.poolToken, _amount);
        }
    }
}
