// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    address[] public aDaiArray = [aDai];
    address[] public aAaveArray = [aAave];
    uint256[] public amountArray = [1 ether];

    function testAllMarketsPauseUnpause() public {
        morpho.setIsPausedForAllMarkets(true);

        for (uint256 i; i < pools.length; ++i) {
            (
                ,
                ,
                ,
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.market(pools[i]);
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
                ,
                ,
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.market(pools[i]);
            assertFalse(isSupplyPaused);
            assertFalse(isBorrowPaused);
            assertFalse(isWithdrawPaused);
            assertFalse(isRepayPaused);
            assertFalse(isLiquidateCollateralPaused);
            assertFalse(isLiquidateBorrowPaused);
        }
    }

    function testShouldTriggerFunctionsWhenNotPaused() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        supplier1.borrow(aUsdc, toBorrow);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(aUsdc, toBorrow);

        (, toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), aUsdc);
        supplier1.borrow(aUsdc, toBorrow);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        uint256 toLiquidate = toBorrow / 2;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(aUsdc, aDai, address(supplier1), toLiquidate);

        supplier1.withdraw(aDai, 1);

        morpho.claimToTreasury(aDaiArray, amountArray);
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
