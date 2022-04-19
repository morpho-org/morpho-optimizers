// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    using CompoundMath for uint256;

    function testOnlyOwnerShouldTriggerPauseFunction() public {
        hevm.expectRevert("LibDiamond: Must be contract owner");
        supplier1.setPauseStatus(dai);

        morphoCompound.setPauseStatus(dai);
        assertTrue(morphoLens.paused(dai), "paused is false");
    }

    function testPauseUnpause() public {
        morphoCompound.setPauseStatus(dai);
        assertTrue(morphoLens.paused(dai), "paused is false");

        morphoCompound.setPauseStatus(dai);
        assertFalse(morphoLens.paused(dai), "paused is true");
    }

    function testShouldTriggerFunctionsWhenNotPaused() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        supplier1.borrow(cUsdc, toBorrow);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(cUsdc, toBorrow);

        (, toBorrow) = morphoLens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        hevm.expectRevert(LibPositionsManager.BorrowOnCompoundFailed.selector);
        supplier1.borrow(cUsdc, toBorrow);

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setUnderlyingPrice(cDai, (oracle.getUnderlyingPrice(cDai) * 95) / 100);

        uint256 toLiquidate = toBorrow / 2;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        hevm.expectRevert(PositionsManagerForCompoundEventsErrors.DebtValueNotAboveMax.selector);
        liquidator.liquidate(cUsdc, cDai, address(supplier1), toLiquidate);

        supplier1.withdraw(cDai, 1 ether);

        hevm.expectRevert(PositionsManagerForCompoundEventsErrors.AmountIsZero.selector);
        morphoCompound.claimToTreasury(cDai);
    }

    function testShouldNotTriggerFunctionsWhenPaused() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, amount);

        (, uint256 toBorrow) = morphoLens.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow);

        morphoCompound.setPauseStatus(cDai);
        morphoCompound.setPauseStatus(cUsdc);

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

        uint256 toLiquidate = (toBorrow - 2) / 2; // Minus 2 only due to roundings.
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        liquidator.liquidate(cUsdc, cDai, address(supplier1), toLiquidate);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        morphoCompound.claimToTreasury(cDai);
    }
}
