// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    using CompoundMath for uint256;

    address[] public cEthArray = [cEth];
    address[] public cDaiArray = [cDai];
    uint256[] public amountArray = [1 ether];

    function testAllMarketsPauseUnpause() public {
        morpho.setIsPausedForAllMarkets(true);

        for (uint256 i; i < pools.length; ++i) {
            (
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.marketStatus(pools[i]);
            assertTrue(isSupplyPaused);
            assertTrue(isBorrowPaused);
            assertTrue(isWithdrawPaused);
            assertTrue(isRepayPaused);
            assertTrue(isLiquidateCollateralPaused);
            assertTrue(isLiquidateBorrowPaused);
        }

        morpho.setIsPausedForAllMarkets(false);

        for (uint256 i; i < pools.length; ++i) {
            (
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.marketStatus(pools[i]);
            assertFalse(isSupplyPaused);
            assertFalse(isBorrowPaused);
            assertFalse(isWithdrawPaused);
            assertFalse(isRepayPaused);
            assertFalse(isLiquidateCollateralPaused);
            assertFalse(isLiquidateBorrowPaused);
        }
    }

    function testShouldTriggerFunctionsWhenNotPaused() public {
        uint256 amount = 100 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        supplier1.borrow(cUsdc, toBorrow);

        moveOneBlockForwardBorrowRepay();

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(cUsdc, type(uint256).max);

        (, toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow - 10); // Here the max capacities is overestimated.

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setUnderlyingPrice(cDai, (oracle.getUnderlyingPrice(cDai) * 97) / 100);

        moveOneBlockForwardBorrowRepay();

        uint256 toLiquidate = toBorrow / 3;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(cUsdc, cDai, address(supplier1), toLiquidate);

        supplier1.withdraw(cDai, 1 ether);

        morpho.claimToTreasury(cDaiArray, amountArray);
    }

    function testShouldDisableAllMarketsWhenGloballyPaused() public {
        morpho.setIsPausedForAllMarkets(true);

        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            vm.expectRevert(abi.encodeWithSignature("SupplyPaused()"));
            supplier1.supply(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("BorrowPaused()"));
            supplier1.borrow(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("WithdrawPaused()"));
            supplier1.withdraw(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("RepayPaused()"));
            supplier1.repay(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("LiquidateCollateralPaused()"));
            supplier1.liquidate(pools[i], pools[0], address(supplier1), 1);
        }
    }

    function testShouldNotPauseSupplyOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsSupplyPaused(address(0), true);
    }

    function testShouldNotPauseBorrowOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsBorrowPaused(address(0), true);
    }

    function testShouldNotPauseWithdrawOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsWithdrawPaused(address(0), true);
    }

    function testShouldNotPauseRepayMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsRepayPaused(address(0), true);
    }

    function testShouldNotPauseLiquidateCollateralOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsLiquidateCollateralPaused(address(0), true);
    }

    function testShouldNotPauseLiquidateBorrowOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsLiquidateBorrowPaused(address(0), true);
    }

    function testShouldNotDeprecatedMarketWhenNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsDeprecated(address(0), true);
    }
}
