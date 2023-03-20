// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    address[] public aDaiArray = [aDai];
    address[] public aAaveArray = [aAave];
    uint256[] public amountArray = [1 ether];

    function testAllMarketsPauseUnpause() public {
        morpho.setIsPausedForAllMarkets(true);

        for (uint256 i; i < pools.length; ++i) {
            (
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.marketPauseStatus(pools[i]);
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
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.marketPauseStatus(pools[i]);
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
        vm.expectRevert(abi.encodeWithSignature("UnauthorisedLiquidate()"));
        liquidator.liquidate(aUsdc, aDai, address(supplier1), toLiquidate);

        supplier1.withdraw(aDai, 1);

        morpho.claimToTreasury(aDaiArray, amountArray);
    }

    function testShouldDisableAllMarketsWhenGloballyPaused() public {
        morpho.setIsPausedForAllMarkets(true);

        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            vm.expectRevert(abi.encodeWithSignature("SupplyIsPaused()"));
            supplier1.supply(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("BorrowIsPaused()"));
            supplier1.borrow(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("WithdrawIsPaused()"));
            supplier1.withdraw(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("RepayIsPaused()"));
            supplier1.repay(pools[i], 1);

            vm.expectRevert(abi.encodeWithSignature("LiquidateCollateralIsPaused()"));
            supplier1.liquidate(pools[i], pools[0], address(supplier1), 1);
        }
    }

    function testBorrowPauseCheckSkipped() public {
        // Deprecate a market.
        morpho.setIsBorrowPaused(aDai, true);
        morpho.setIsDeprecated(aDai, true);
        (, bool isBorrowPaused, , , , , bool isDeprecated) = morpho.marketPauseStatus(aDai);

        assertTrue(isBorrowPaused);
        assertTrue(isDeprecated);

        morpho.setIsPausedForAllMarkets(false);
        (, isBorrowPaused, , , , , isDeprecated) = morpho.marketPauseStatus(aDai);

        assertTrue(isBorrowPaused);
        assertTrue(isDeprecated);

        morpho.setIsPausedForAllMarkets(true);
        (, isBorrowPaused, , , , , isDeprecated) = morpho.marketPauseStatus(aDai);

        assertTrue(isBorrowPaused);
        assertTrue(isDeprecated);
    }

    function testPauseSupply() public {
        uint256 amount = 10_000 ether;
        morpho.setIsSupplyPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("SupplyIsPaused()"));
        supplier1.supply(aDai, amount);
    }

    function testPauseBorrow() public {
        uint256 amount = 10_000 ether;
        morpho.setIsBorrowPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("BorrowIsPaused()"));
        supplier1.borrow(aDai, amount);
    }

    function testPauseWithdraw() public {
        uint256 amount = 10_000 ether;
        morpho.setIsWithdrawPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("WithdrawIsPaused()"));
        supplier1.withdraw(aDai, amount);
    }

    function testPauseRepay() public {
        uint256 amount = 10_000 ether;
        morpho.setIsRepayPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("RepayIsPaused()"));
        supplier1.repay(aDai, amount);
    }

    function testPauseLiquidateCollateral() public {
        uint256 amount = 10_000 ether;
        morpho.setIsLiquidateCollateralPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("LiquidateCollateralIsPaused()"));
        supplier1.liquidate(aUsdc, aDai, address(supplier2), amount);
    }

    function testPauseLiquidateBorrow() public {
        uint256 amount = 10_000 ether;
        morpho.setIsLiquidateBorrowPaused(aDai, true);

        vm.expectRevert(abi.encodeWithSignature("LiquidateBorrowIsPaused()"));
        supplier1.liquidate(aDai, aUsdc, address(supplier2), amount);
    }

    function testShouldNotPauseSupplyOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsSupplyPaused(address(1), true);
    }

    function testShouldNotPauseBorrowOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsBorrowPaused(address(1), true);
    }

    function testShouldNotPauseWithdrawOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsWithdrawPaused(address(1), true);
    }

    function testShouldNotPauseRepayMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsRepayPaused(address(1), true);
    }

    function testShouldNotPauseLiquidateCollateralOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsLiquidateCollateralPaused(address(1), true);
    }

    function testShouldNotPauseLiquidateBorrowOnMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsLiquidateBorrowPaused(address(1), true);
    }

    function testShouldNotDeprecatedMarketWhenNotCreated() public {
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.setIsDeprecated(address(1), true);
    }
}
