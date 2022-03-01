// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    function test_only_markets_owner_can_trigger_pause_function() public {
        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManagerOwner()"));
        supplier1.setPauseStatus(aDai);

        positionsManager.setPauseStatus(aDai);
        assertTrue(positionsManager.paused(aDai), "paused is false");
    }

    function test_pause_unpause() public {
        positionsManager.setPauseStatus(aDai);
        assertTrue(positionsManager.paused(aDai), "paused is false");

        positionsManager.setPauseStatus(aDai);
        assertFalse(positionsManager.paused(aDai), "paused is true");
    }

    function test_ability_to_trigger_functions_when_not_paused() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        supplier1.borrow(aUsdc, toBorrow);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(aUsdc, toBorrow);

        (, toBorrow) = positionsManager.getUserMaxCapacitiesForAsset(address(supplier1), aUsdc);
        supplier1.borrow(aUsdc, toBorrow);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        uint256 toLiquidate = toBorrow / 2;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(aUsdc, aDai, address(supplier1), toLiquidate);

        supplier1.withdraw(aDai, 1);

        positionsManager.claimToTreasury(aDai);
    }

    function test_not_possible_to_trigger_functions_when_paused() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(aDai, amount);

        (, uint256 toBorrow) = positionsManager.getUserMaxCapacitiesForAsset(
            address(supplier1),
            aUsdc
        );
        supplier1.borrow(aUsdc, toBorrow);

        positionsManager.setPauseStatus(aDai);
        positionsManager.setPauseStatus(aUsdc);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(aDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(aUsdc, 0);

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

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        positionsManager.claimToTreasury(aDai);
    }
}
