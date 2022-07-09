// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    address[] public aDaiArray = [aDai];
    address[] public aAaveArray = [aAave];
    uint256[] public amountArray = [1 ether];

    function testOnlyOwnerShouldTriggerPauseFunction() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setPauseStatus(aDai, true);

        morpho.setPauseStatus(aDai, true);
        (, bool isPaused, ) = morpho.marketStatus(aDai);
        assertTrue(isPaused, "paused is false");
    }

    function testOnlyOwnerShouldTriggerPartialPauseFunction() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setPartialPauseStatus(aDai, true);

        morpho.setPartialPauseStatus(aDai, true);
        (, , bool isPartiallyPaused) = morpho.marketStatus(aDai);
        assertTrue(isPartiallyPaused, "partial paused is false");
    }

    function testPauseUnpause() public {
        morpho.setPauseStatus(aDai, true);
        (, bool isPaused, ) = morpho.marketStatus(aDai);
        assertTrue(isPaused, "paused is false");

        morpho.setPauseStatus(aDai, false);
        (, isPaused, ) = morpho.marketStatus(aDai);
        assertFalse(isPaused, "paused is true");
    }

    function testPartialPausePartialUnpause() public {
        morpho.setPartialPauseStatus(aDai, true);
        (, , bool isPartiallyPaused) = morpho.marketStatus(aDai);
        assertTrue(isPartiallyPaused, "partial paused is false");

        morpho.setPartialPauseStatus(aDai, false);
        (, , isPartiallyPaused) = morpho.marketStatus(aDai);
        assertFalse(isPartiallyPaused, "partial paused is true");
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
        morpho.setPauseStatusForAllMarkets(true);

        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.supply(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.borrow(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.withdraw(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.repay(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.liquidate(pools[i], pools[0], address(supplier1), 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.liquidate(pools[0], pools[i], address(supplier1), 1);
        }
    }

    function testShouldDisableMarketWhenPaused() public {
        // TODO: fix that.
        deal(usdt, address(morpho), 1);

        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(aDai, amount);

        (, uint256 toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), aUsdc);
        supplier1.borrow(aUsdc, toBorrow);

        morpho.setPauseStatus(aDai, true);
        morpho.setPauseStatus(aUsdc, true);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(aDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(aUsdc, 1);

        supplier1.approve(usdc, toBorrow);
        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.repay(aUsdc, toBorrow);
        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.withdraw(aDai, 1);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        uint256 toLiquidate = toBorrow / 2;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        liquidator.liquidate(aUsdc, aDai, address(supplier1), toLiquidate);

        morpho.claimToTreasury(aDaiArray, amountArray);

        // Functions on other markets should still be enabled.
        amount = 10 ether;
        toBorrow = to6Decimals(amount / 2);

        supplier1.approve(aave, amount);
        supplier1.supply(aAave, amount);

        supplier1.borrow(aUsdt, toBorrow);

        supplier1.approve(usdt, toBorrow);
        supplier1.repay(aUsdt, toBorrow / 2);

        toLiquidate = 1_000;
        liquidator.approve(usdt, toLiquidate);
        hevm.expectRevert(ExitPositionsManager.UnauthorisedLiquidate.selector);
        liquidator.liquidate(aUsdt, aAave, address(supplier1), toLiquidate);

        supplier1.withdraw(aAave, 1 ether);

        morpho.claimToTreasury(aAaveArray, amountArray);
    }

    function testShouldOnlyEnableRepayWithdrawLiquidateWhenPartiallyPaused() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(aDai, amount);

        (, uint256 toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), aUsdc);
        supplier1.borrow(aUsdc, toBorrow);

        morpho.setPartialPauseStatus(aDai, true);
        morpho.setPartialPauseStatus(aUsdc, true);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(aDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(aUsdc, 1);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(aUsdc, 1e6);
        supplier1.withdraw(aDai, 1 ether);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        uint256 toLiquidate = toBorrow / 3;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(aUsdc, aDai, address(supplier1), toLiquidate);

        morpho.claimToTreasury(aDaiArray, amountArray);

        // Functions on other markets should still be enabled.
        amount = 10 ether;
        toBorrow = to6Decimals(amount / 2);

        supplier1.approve(aave, amount);
        supplier1.supply(aAave, amount);

        supplier1.borrow(aUsdt, toBorrow);

        supplier1.approve(usdt, toBorrow);
        supplier1.repay(aUsdt, toBorrow / 2);

        customOracle.setDirectPrice(aave, (oracle.getAssetPrice(aave) * 97) / 100);

        toLiquidate = 10_000;
        liquidator.approve(usdt, toLiquidate);
        hevm.expectRevert(ExitPositionsManager.UnauthorisedLiquidate.selector);
        liquidator.liquidate(aUsdt, aAave, address(supplier1), toLiquidate);

        supplier1.withdraw(aAave, 1 ether);

        morpho.claimToTreasury(aAaveArray, amountArray);
    }
}
