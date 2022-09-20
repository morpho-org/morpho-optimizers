// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestWithdraw is TestSetup {
    using WadRayMath for uint256;

    struct WithdrawTest {
        ERC20 underlying;
        IAToken poolToken;
        uint256 decimals;
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

    function _testShouldWithdrawMarketP2PAndOnPool(address _poolToken, uint96 _amount) internal {
        WithdrawTest memory test;
        test.poolToken = IAToken(_poolToken);
        test.underlying = ERC20(test.poolToken.UNDERLYING_ASSET_ADDRESS());
        test.decimals = test.underlying.decimals();

        test.morphoBalanceOnPoolBefore = test.poolToken.balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = test.underlying.balanceOf(address(morpho));

        uint256 amount = bound(
            _amount,
            10**(test.decimals - 4),
            test.underlying.balanceOf(address(this))
        );

        _tip(address(test.underlying), address(supplier1), amount);

        supplier1.approve(address(test.underlying), amount);
        supplier1.supply(address(test.poolToken), amount);

        test.p2pSupplyIndex = morpho.p2pSupplyIndex(address(test.poolToken));
        (, test.poolSupplyIndex, ) = morpho.poolIndexes(address(test.poolToken));

        (test.balanceInP2P, test.balanceOnPool) = morpho.supplyBalanceInOf(
            address(test.poolToken),
            address(supplier1)
        );

        test.underlyingInP2PBefore = test.balanceInP2P.rayMul(test.p2pSupplyIndex);
        test.underlyingOnPoolBefore = test.balanceOnPool.rayMul(test.poolSupplyIndex);
        test.totalUnderlyingBefore = test.underlyingOnPoolBefore + test.underlyingInP2PBefore;

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 60 * 60 * 24);

        morpho.updateIndexes(address(test.poolToken));

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 60 * 60 * 24);

        assertEq(
            test.underlying.balanceOf(address(supplier1)),
            0,
            "unexpected underlying balance before withdraw"
        );

        supplier1.withdraw(address(test.poolToken), test.totalUnderlyingBefore);

        (test.underlyingInP2PAfter, test.underlyingOnPoolAfter, test.totalUnderlyingAfter) = lens
            .getCurrentSupplyBalanceInOf(address(test.poolToken), address(supplier1));

        assertApproxEqAbs(
            test.underlying.balanceOf(address(supplier1)),
            test.totalUnderlyingBefore,
            10,
            "unexpected underlying balance after withdraw"
        );

        if (test.totalUnderlyingAfter > 0) {
            supplier1.withdraw(address(test.poolToken), test.totalUnderlyingBefore); // Withdraw accrued interests.

            (
                test.underlyingInP2PAfter,
                test.underlyingOnPoolAfter,
                test.totalUnderlyingAfter
            ) = lens.getCurrentSupplyBalanceInOf(address(test.poolToken), address(supplier1));
        }

        assertEq(test.underlyingOnPoolAfter, 0, "unexpected pool underlying balance");
        assertEq(test.underlyingInP2PAfter, 0, "unexpected p2p underlying balance");
        assertEq(test.totalUnderlyingAfter, 0, "unexpected total underlying supplied");
    }

    function testShouldWithdrawAllMarketsP2PAndOnPool(uint8 _marketIndex, uint96 _amount) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();

        _marketIndex = uint8(_marketIndex % activeMarkets.length);

        _testShouldWithdrawMarketP2PAndOnPool(activeMarkets[_marketIndex], _amount);
    }

    function testShouldNotWithdrawZeroAmount() public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            WithdrawTest memory test;
            test.poolToken = IAToken(activeMarkets[marketIndex]);

            vm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
            supplier1.withdraw(address(test.poolToken), 0);
        }
    }

    function testShouldNotWithdrawFromUnenteredMarket(uint96 _amount) public {
        vm.assume(_amount > 0);

        address[] memory activeMarkets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            WithdrawTest memory test;
            test.poolToken = IAToken(activeMarkets[marketIndex]);

            vm.expectRevert(ExitPositionsManager.UserNotMemberOfMarket.selector);
            supplier1.withdraw(address(test.poolToken), _amount);
        }
    }
}
