// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    using CompoundMath for uint256;

    function testOnlyOwnerShouldTriggerPauseFunction() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.togglePauseStatus(dai);

        morpho.togglePauseStatus(dai);
        (, bool isPaused, ) = morpho.marketStatuses(dai);
        assertTrue(isPaused, "paused is false");
    }

    function testOnlyOwnerShouldTriggerPartialPauseFunction() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.togglePartialPauseStatus(dai);

        morpho.togglePartialPauseStatus(dai);
        (, , bool isPartiallyPaused) = morpho.marketStatuses(dai);
        assertTrue(isPartiallyPaused, "partial paused is false");
    }

    function testPauseUnpause() public {
        morpho.togglePauseStatus(dai);
        (, bool isPaused, ) = morpho.marketStatuses(dai);
        assertTrue(isPaused, "paused is false");

        morpho.togglePauseStatus(dai);
        (, isPaused, ) = morpho.marketStatuses(dai);
        assertFalse(isPaused, "paused is true");
    }

    function testPartialPausePartialUnpause() public {
        morpho.togglePartialPauseStatus(dai);
        (, , bool isPartiallyPaused) = morpho.marketStatuses(dai);
        assertTrue(isPartiallyPaused, "partial paused is false");

        morpho.togglePartialPauseStatus(dai);
        (, , isPartiallyPaused) = morpho.marketStatuses(dai);
        assertFalse(isPartiallyPaused, "partial paused is true");
    }

    function testShouldTriggerFunctionsWhenNotPaused() public {
        uint256 amount = 100 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        supplier1.borrow(cUsdc, toBorrow);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(cUsdc, type(uint256).max);

        (, toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow - 10); // Here the max capacities is overestimated.

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setUnderlyingPrice(cDai, (oracle.getUnderlyingPrice(cDai) * 97) / 100);

        uint256 toLiquidate = toBorrow / 3;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(cUsdc, cDai, address(supplier1), toLiquidate);

        supplier1.withdraw(cDai, 1 ether);

        hevm.expectRevert(MorphoEventsErrors.AmountIsZero.selector);
        morpho.claimToTreasury(cDai, 1 ether);
    }

    function testShouldDisableMarketWhenPaused() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, amount);

        (, uint256 toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow);

        morpho.togglePauseStatus(cDai);
        morpho.togglePauseStatus(cUsdc);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(cUsdc, 1);

        supplier1.approve(usdc, toBorrow);
        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.repay(cUsdc, toBorrow);
        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.withdraw(cDai, 1);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setUnderlyingPrice(cDai, (oracle.getUnderlyingPrice(cDai) * 95) / 100);

        uint256 toLiquidate = toBorrow / 3;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        liquidator.liquidate(cUsdc, cDai, address(supplier1), toLiquidate);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        morpho.claimToTreasury(cDai, 1 ether);

        // Functions on other markets should still be enabled.
        amount = 10 ether;
        to6Decimals(amount / 2);

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);

        supplier1.borrow(cUsdt, toBorrow);

        supplier1.approve(usdt, toBorrow);
        supplier1.repay(cUsdt, toBorrow / 2);

        customOracle.setUnderlyingPrice(cEth, (oracle.getUnderlyingPrice(cEth) * 97) / 100);

        toLiquidate = 1_000;
        liquidator.approve(usdt, toLiquidate);
        hevm.expectRevert(PositionsManager.DebtValueNotAboveMax.selector);
        liquidator.liquidate(cUsdt, cEth, address(supplier1), toLiquidate);

        supplier1.withdraw(cEth, 1 ether);

        hevm.expectRevert(MorphoEventsErrors.AmountIsZero.selector);
        morpho.claimToTreasury(cEth, 1 ether);
    }

    function testShouldOnlyEnableRepayWithdrawLiquidateWhenPartiallyPaused() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, amount);

        (, uint256 toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow);

        morpho.togglePartialPauseStatus(cDai);
        morpho.togglePartialPauseStatus(cUsdc);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(cUsdc, 1);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(cUsdc, 1e6);
        supplier1.withdraw(cDai, 1 ether);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setUnderlyingPrice(cDai, (oracle.getUnderlyingPrice(cDai) * 97) / 100);

        uint256 toLiquidate = toBorrow / 3;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(cUsdc, cDai, address(supplier1), toLiquidate);

        // Does not revert because the market is paused.
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        morpho.claimToTreasury(cDai, 1 ether);

        // Functions on other markets should still be enabled.
        amount = 10 ether;
        toBorrow = to6Decimals(amount / 2);

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);

        supplier1.borrow(cUsdt, toBorrow);

        supplier1.approve(usdt, toBorrow);
        supplier1.repay(cUsdt, toBorrow / 2);

        customOracle.setUnderlyingPrice(cEth, (oracle.getUnderlyingPrice(cEth) * 97) / 100);

        toLiquidate = 10_000;
        liquidator.approve(usdt, toLiquidate);
        hevm.expectRevert(PositionsManager.DebtValueNotAboveMax.selector);
        liquidator.liquidate(cUsdt, cEth, address(supplier1), toLiquidate);

        supplier1.withdraw(cEth, 1 ether);

        hevm.expectRevert(MorphoEventsErrors.AmountIsZero.selector);
        morpho.claimToTreasury(cEth, 1 ether);
    }
}
