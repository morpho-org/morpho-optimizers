// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestSupply is TestSetup {
    using WadRayMath for uint256;

    struct SupplyTest {
        ERC20 underlying;
        IAToken poolToken;
        IVariableDebtToken variablePoolToken;
        uint256 decimals;
        uint256 morphoBalanceOnPoolBefore;
        uint256 morphoBorrowOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        bool p2pDisabled;
        uint256 p2pBorrowDelta;
        uint256 supplyRatePerYear;
        uint256 p2pSupplyRatePerYear;
        uint256 poolSupplyRatePerYear;
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        uint256 unclaimedRewardsBefore;
        uint256 underlyingOnPoolBefore;
        uint256 underlyingInP2PBefore;
        uint256 totalUnderlyingBefore;
        uint256 underlyingOnPoolAfter;
        uint256 underlyingInP2PAfter;
        uint256 totalUnderlyingAfter;
    }

    function _testShouldSupplyMarketP2PAndOnPool(address _poolToken, uint96 _amount) internal {
        SupplyTest memory test;
        test.poolToken = IAToken(_poolToken);
        test.underlying = ERC20(test.poolToken.UNDERLYING_ASSET_ADDRESS());
        test.variablePoolToken = IVariableDebtToken(
            pool.getReserveData(address(test.underlying)).variableDebtTokenAddress
        );
        test.decimals = test.underlying.decimals();

        (, test.p2pBorrowDelta, , ) = morpho.deltas(address(test.poolToken));
        (, , , , , , test.p2pDisabled) = morpho.market(address(test.poolToken));
        test.morphoBalanceOnPoolBefore = test.poolToken.scaledBalanceOf(address(morpho));
        test.morphoBorrowOnPoolBefore = test
        .variablePoolToken
        .scaledBalanceOf(address(morpho))
        .rayMul(pool.getReserveNormalizedVariableDebt(address(test.underlying)));
        test.morphoUnderlyingBalanceBefore = test.underlying.balanceOf(address(morpho));

        uint256 amount = bound(
            _amount,
            10**(test.decimals - 6),
            test.underlying.balanceOf(address(this))
        );

        _tip(address(test.underlying), address(supplier1), amount);

        supplier1.approve(address(test.underlying), amount);
        supplier1.supply(address(test.poolToken), amount);

        test.p2pSupplyIndex = morpho.p2pSupplyIndex(address(test.poolToken));
        (, test.poolSupplyIndex, test.poolBorrowIndex) = morpho.poolIndexes(
            address(test.poolToken)
        );
        test.supplyRatePerYear = lens.getCurrentUserSupplyRatePerYear(
            address(test.poolToken),
            address(supplier1)
        );
        (test.p2pSupplyRatePerYear, , test.poolSupplyRatePerYear, ) = lens.getRatesPerYear(
            address(test.poolToken)
        );

        (test.balanceInP2P, test.balanceOnPool) = morpho.supplyBalanceInOf(
            address(test.poolToken),
            address(supplier1)
        );

        test.underlyingInP2PBefore = test.balanceInP2P.rayMul(test.p2pSupplyIndex);
        test.underlyingOnPoolBefore = test.balanceOnPool.rayMul(test.poolSupplyIndex);
        test.totalUnderlyingBefore = test.underlyingOnPoolBefore + test.underlyingInP2PBefore;

        assertEq(
            test.underlying.balanceOf(address(supplier1)),
            0,
            "unexpected underlying balance after"
        );
        assertApproxEqAbs(
            test.totalUnderlyingBefore,
            amount,
            1,
            "unexpected total supplied amount"
        );
        if (test.p2pDisabled) assertEq(test.balanceInP2P, 0, "expected no match");

        address[] memory poolTokens = new address[](1);
        poolTokens[0] = address(test.poolToken);
        if (address(rewardsManager) != address(0)) {
            test.unclaimedRewardsBefore = rewardsManager.getUserUnclaimedRewards(
                poolTokens,
                address(supplier1)
            );

            assertEq(test.unclaimedRewardsBefore, 0, "unclaimed rewards not zero");
        }

        assertApproxEqAbs(
            test.variablePoolToken.scaledBalanceOf(address(morpho)).rayMul(test.poolBorrowIndex) +
                test.underlyingInP2PBefore,
            test.morphoBorrowOnPoolBefore,
            10**(test.decimals / 2),
            "unexpected morpho borrow balance"
        );

        if (test.p2pBorrowDelta <= amount.rayDiv(test.poolBorrowIndex))
            assertGe(
                test.underlyingInP2PBefore,
                test.p2pBorrowDelta.rayMul(test.poolBorrowIndex),
                "expected p2p borrow delta minimum match"
            );
        else
            assertApproxEqAbs(
                test.underlyingInP2PBefore,
                amount,
                10**(test.decimals / 2),
                "expected full match"
            );

        assertEq(
            test.underlying.balanceOf(address(morpho)),
            test.morphoUnderlyingBalanceBefore,
            "unexpected morpho underlying balance"
        );
        assertApproxEqAbs(
            test.poolToken.scaledBalanceOf(address(morpho)),
            test.morphoBalanceOnPoolBefore + test.balanceOnPool,
            10,
            "unexpected morpho underlying balance on pool"
        );

        vm.roll(block.number + 500);
        vm.warp(block.timestamp + 60 * 60 * 24);

        morpho.updateIndexes(address(test.poolToken));

        vm.roll(block.number + 500);
        vm.warp(block.timestamp + 60 * 60 * 24);

        (test.underlyingInP2PAfter, test.underlyingOnPoolAfter, test.totalUnderlyingAfter) = lens
        .getCurrentSupplyBalanceInOf(address(test.poolToken), address(supplier1));

        uint256 expectedUnderlyingOnPoolAfter = test.underlyingOnPoolBefore.rayMul(
            1e27 + (test.poolSupplyRatePerYear * 60 * 60 * 48) / 365 days
        );
        uint256 expectedUnderlyingInP2PAfter = test.underlyingInP2PBefore.rayMul(
            1e27 + (test.p2pSupplyRatePerYear * 60 * 60 * 48) / 365 days
        );
        uint256 expectedTotalUnderlyingAfter = test.totalUnderlyingBefore.rayMul(
            1e27 + (test.supplyRatePerYear * 60 * 60 * 48) / 365 days
        );

        assertApproxEqAbs(
            test.underlyingOnPoolAfter,
            expectedUnderlyingOnPoolAfter,
            test.underlyingOnPoolAfter / 1e9 + 1e4,
            "unexpected pool underlying amount"
        );
        assertApproxEqAbs(
            test.underlyingInP2PAfter,
            expectedUnderlyingInP2PAfter,
            test.underlyingInP2PAfter / 1e9 + 1e4,
            "unexpected p2p underlying amount"
        );
        assertApproxEqAbs(
            test.totalUnderlyingAfter,
            expectedTotalUnderlyingAfter,
            test.totalUnderlyingAfter / 1e9 + 1e4,
            "unexpected total underlying amount from avg supply rate"
        );
        assertApproxEqAbs(
            test.totalUnderlyingAfter,
            expectedUnderlyingOnPoolAfter + expectedUnderlyingInP2PAfter,
            test.totalUnderlyingBefore / 1e9 + 1e4,
            "unexpected total underlying amount"
        );
        if (
            address(rewardsManager) != address(0) &&
            test.underlyingOnPoolAfter > 0 &&
            block.timestamp < aaveIncentivesController.DISTRIBUTION_END()
        )
            assertGt(
                rewardsManager.getUserUnclaimedRewards(poolTokens, address(supplier1)),
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
            test.poolToken = IAToken(activeMarkets[marketIndex]);

            vm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
            supplier1.supply(address(test.poolToken), 0);
        }
    }

    function testShouldNotSupplyOnBehalfAddressZero(uint96 _amount) public {
        address[] memory activeMarkets = getAllFullyActiveMarkets();

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            SupplyTest memory test;
            test.poolToken = IAToken(activeMarkets[marketIndex]);
            test.underlying = ERC20(test.poolToken.UNDERLYING_ASSET_ADDRESS());
            test.decimals = test.underlying.decimals();

            uint256 amount = bound(_amount, 10**(test.decimals - 6), type(uint96).max);

            vm.expectRevert(PositionsManagerUtils.AddressIsZero.selector);
            supplier1.supply(address(test.poolToken), address(0), amount);
        }
    }
}
