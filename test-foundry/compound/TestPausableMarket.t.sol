// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    using CompoundMath for uint256;

    address[] cEthArray = [cEth];
    address[] cDaiArray = [cDai];
    uint256[] public amountArray = [1 ether];

    function testOnlyOwnerShouldTriggerPauseFunction() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setPauseStatus(cDai, true);

        morpho.setPauseStatus(cDai, true);
        (, bool isPaused, ) = morpho.marketStatus(cDai);
        assertTrue(isPaused, "paused is false");
    }

    function testOnlyOwnerShouldTriggerPartialPauseFunction() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setPartialPauseStatus(cDai, true);

        morpho.setPartialPauseStatus(cDai, true);
        (, , bool isPartiallyPaused) = morpho.marketStatus(cDai);
        assertTrue(isPartiallyPaused, "partial paused is false");
    }

    function testPauseUnpause() public {
        morpho.setPauseStatus(cDai, true);
        (, bool isPaused, ) = morpho.marketStatus(cDai);
        assertTrue(isPaused, "paused is false");

        morpho.setPauseStatus(cDai, false);
        (, isPaused, ) = morpho.marketStatus(cDai);
        assertFalse(isPaused, "paused is true");
    }

    function testPartialPausePartialUnpause() public {
        morpho.setPartialPauseStatus(cDai, true);
        (, , bool isPartiallyPaused) = morpho.marketStatus(cDai);
        assertTrue(isPartiallyPaused, "partial paused is false");

        morpho.setPartialPauseStatus(cDai, false);
        (, , isPartiallyPaused) = morpho.marketStatus(cDai);
        assertFalse(isPartiallyPaused, "partial paused is true");
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
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, amount);

        (, uint256 toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow);

        morpho.setPauseStatus(cDai, true);
        morpho.setPauseStatus(cUsdc, true);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(cUsdc, 1);

        supplier1.approve(usdc, toBorrow);
        moveOneBlockForwardBorrowRepay();
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

        morpho.claimToTreasury(cDaiArray, amountArray);

        // Functions on other markets should still be enabled.
        amount = 10 ether;
        to6Decimals(amount / 2);

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);

        supplier1.borrow(cUsdt, toBorrow);

        moveOneBlockForwardBorrowRepay();

        supplier1.approve(usdt, toBorrow);
        supplier1.repay(cUsdt, toBorrow / 2);

        customOracle.setUnderlyingPrice(cEth, (oracle.getUnderlyingPrice(cEth) * 97) / 100);

        toLiquidate = 1_000;
        liquidator.approve(usdt, toLiquidate);
        hevm.expectRevert(PositionsManager.UnauthorisedLiquidate.selector);
        liquidator.liquidate(cUsdt, cEth, address(supplier1), toLiquidate);

        supplier1.withdraw(cEth, 1 ether);

        morpho.claimToTreasury(cEthArray, amountArray);
    }

    function testShouldOnlyEnableRepayWithdrawLiquidateWhenPartiallyPaused() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, amount);

        (, uint256 toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow);

        morpho.setPartialPauseStatus(cDai, true);
        morpho.setPartialPauseStatus(cUsdc, true);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(cUsdc, 1);

        moveOneBlockForwardBorrowRepay();

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

        morpho.claimToTreasury(cDaiArray, amountArray);

        // Functions on other markets should still be enabled.
        amount = 10 ether;
        toBorrow = to6Decimals(amount / 2);

        supplier1.approve(wEth, amount);
        supplier1.supply(cEth, amount);

        supplier1.borrow(cUsdt, toBorrow);

        moveOneBlockForwardBorrowRepay();

        supplier1.approve(usdt, toBorrow);
        supplier1.repay(cUsdt, toBorrow / 2);

        customOracle.setUnderlyingPrice(cEth, (oracle.getUnderlyingPrice(cEth) * 97) / 100);

        toLiquidate = 10_000;
        liquidator.approve(usdt, toLiquidate);
        hevm.expectRevert(PositionsManager.UnauthorisedLiquidate.selector);
        liquidator.liquidate(cUsdt, cEth, address(supplier1), toLiquidate);

        supplier1.withdraw(cEth, 1 ether);

        morpho.claimToTreasury(cEthArray, amountArray);
    }
}
