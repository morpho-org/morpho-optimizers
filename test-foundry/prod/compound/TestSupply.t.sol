// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using CompoundMath for uint256;

    struct SupplyTest {
        ERC20 underlying;
        ICToken poolToken;
        uint256 decimals;
        uint256 morphoBalanceOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        uint256 supplyRatePerBlock;
        uint256 p2pSupplyRatePerBlock;
        uint256 poolSupplyRatePerBlock;
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

    function _testShouldSupplyMarketP2PAndOnPool(address _poolToken, uint96 _amount) internal {
        SupplyTest memory test;
        test.poolToken = ICToken(_poolToken);
        (test.underlying, test.decimals) = _getUnderlying(_poolToken);

        test.morphoBalanceOnPoolBefore = test.poolToken.balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = test.underlying.balanceOf(address(morpho));

        uint256 amount = bound(_amount, 10**(test.decimals - 6), type(uint96).max);

        if (address(test.underlying) == wEth) hoax(wEth, amount);
        deal(address(test.underlying), address(supplier1), amount);

        supplier1.approve(address(test.underlying), amount);
        supplier1.supply(address(test.poolToken), amount);

        test.p2pSupplyIndex = morpho.p2pSupplyIndex(address(test.poolToken));
        test.poolSupplyIndex = test.poolToken.exchangeRateCurrent();
        test.supplyRatePerBlock = lens.getCurrentUserSupplyRatePerBlock(
            address(test.poolToken),
            address(supplier1)
        );
        (test.p2pSupplyRatePerBlock, , test.poolSupplyRatePerBlock, ) = lens.getRatesPerBlock(
            address(test.poolToken)
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.supplyBalanceInOf(
            address(test.poolToken),
            address(supplier1)
        );

        address[] memory poolTokens = new address[](1);
        poolTokens[0] = address(test.poolToken);
        test.unclaimedRewardsBefore = lens.getUserUnclaimedRewards(poolTokens, address(supplier1));

        test.underlyingInP2PBefore = test.balanceInP2P.mul(test.p2pSupplyIndex);
        test.underlyingOnPoolBefore = test.balanceOnPool.mul(test.poolSupplyIndex);
        test.totalUnderlyingBefore = test.underlyingOnPoolBefore + test.underlyingInP2PBefore;

        assertEq(
            test.underlying.balanceOf(address(supplier1)),
            0,
            "unexpected underlying balance after"
        );
        assertLe(
            test.underlyingOnPoolBefore + test.underlyingInP2PBefore,
            amount,
            "greater supplied amount than expected"
        );
        assertGe(
            test.underlyingOnPoolBefore + test.underlyingInP2PBefore + 10**(test.decimals / 2),
            amount,
            "unexpected supplied amount"
        );
        if (morpho.p2pDisabled(address(test.poolToken)))
            assertEq(test.balanceInP2P, 0, "unexpected p2p balance");
        assertEq(test.unclaimedRewardsBefore, 0, "unclaimed rewards not zero");

        assertEq( // TODO: check supply delta
            test.underlying.balanceOf(address(morpho)),
            test.morphoUnderlyingBalanceBefore,
            "unexpected morpho underlying balance"
        );
        assertEq(
            test.poolToken.balanceOf(address(morpho)) - test.morphoBalanceOnPoolBefore,
            test.balanceOnPool,
            "unexpected morpho underlying balance on pool"
        );

        vm.roll(block.number + 500);

        morpho.updateP2PIndexes(address(test.poolToken));

        vm.roll(block.number + 500);

        test.unclaimedRewardsAfter = lens.getUserUnclaimedRewards(poolTokens, address(supplier1));
        (test.underlyingOnPoolAfter, test.underlyingInP2PAfter, test.totalUnderlyingAfter) = lens
        .getCurrentSupplyBalanceInOf(address(test.poolToken), address(supplier1));

        for (uint256 i; i < 1_000; ++i) {
            test.totalUnderlyingBefore = test.totalUnderlyingBefore.mul(
                1e18 + test.supplyRatePerBlock
            );
            test.underlyingOnPoolBefore = test.underlyingOnPoolBefore.mul(
                1e18 + test.poolSupplyRatePerBlock
            );
            test.underlyingInP2PBefore = test.underlyingInP2PBefore.mul(
                1e18 + test.p2pSupplyRatePerBlock
            );
        }

        assertApproxEqAbs(
            test.underlyingOnPoolBefore,
            test.underlyingOnPoolAfter,
            test.underlyingOnPoolBefore / 1e9 + 1e4,
            "unexpected pool underlying amount"
        );
        assertApproxEqAbs(
            test.underlyingInP2PBefore,
            test.underlyingInP2PAfter,
            test.underlyingInP2PBefore / 1e9 + 1e4,
            "unexpected p2p underlying amount"
        );
        assertApproxEqAbs(
            test.totalUnderlyingBefore,
            test.totalUnderlyingAfter,
            test.totalUnderlyingBefore / 1e9 + 1e4,
            "unexpected total underlying amount from avg supply rate"
        );
        assertApproxEqAbs(
            test.underlyingInP2PBefore + test.underlyingOnPoolBefore,
            test.totalUnderlyingAfter,
            test.totalUnderlyingBefore / 1e9 + 1e4,
            "unexpected total underlying amount"
        );
        if (
            test.underlyingOnPoolAfter > 0 &&
            morpho.comptroller().compSupplySpeeds(address(test.poolToken)) > 0
        )
            assertGt(
                test.unclaimedRewardsAfter,
                test.unclaimedRewardsBefore,
                "lower unclaimed rewards"
            );
    }

    function testShouldSupplyAllMarketsP2PAndOnPool(uint8 _marketIndex, uint96 _amount) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();

        _marketIndex = uint8(_marketIndex % activeMarkets.length);

        _testShouldSupplyMarketP2PAndOnPool(activeMarkets[_marketIndex], _amount);
    }

    function testShouldNotSupplyZeroAmount() public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            SupplyTest memory test;
            test.poolToken = ICToken(activeMarkets[marketIndex]);

            vm.expectRevert(PositionsManager.AmountIsZero.selector);
            supplier1.supply(address(test.poolToken), 0);
        }
    }

    function testShouldNotSupplyOnBehalfAddressZero(uint96 _amount) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            SupplyTest memory test;
            test.poolToken = ICToken(activeMarkets[marketIndex]);
            (test.underlying, test.decimals) = _getUnderlying(activeMarkets[marketIndex]);

            uint256 amount = bound(_amount, 10**(test.decimals - 6), type(uint96).max);

            vm.expectRevert(PositionsManager.AddressIsZero.selector);
            supplier1.supply(address(test.poolToken), address(0), amount);
        }
    }
}
