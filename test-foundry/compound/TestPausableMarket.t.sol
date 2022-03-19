// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    using CompoundMath for uint256;

    function test_only_markets_owner_can_trigger_pause_function() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setPauseStatus(dai);

        positionsManager.setPauseStatus(dai);
        assertTrue(positionsManager.paused(dai), "paused is false");
    }

    function test_pause_unpause() public {
        positionsManager.setPauseStatus(dai);
        assertTrue(positionsManager.paused(dai), "paused is false");

        positionsManager.setPauseStatus(dai);
        assertFalse(positionsManager.paused(dai), "paused is true");
    }

    function test_ability_to_trigger_functions_when_not_paused() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        supplier1.borrow(cUsdc, toBorrow);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(cUsdc, toBorrow);

        (, toBorrow) = positionsManager.getUserMaxCapacitiesForAsset(address(supplier1), cUsdc);
        supplier1.borrow(cUsdc, toBorrow);

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setUnderlyingPrice(cDai, (oracle.getUnderlyingPrice(cDai) * 95) / 100);

        uint256 toLiquidate = toBorrow / 2;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(cUsdc, cDai, address(supplier1), toLiquidate);

        supplier1.withdraw(cDai, 1 ether);

        positionsManager.claimToTreasury(cDai);
    }

    function test_not_possible_to_trigger_functions_when_paused() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, amount);

        (, uint256 toBorrow) = positionsManager.getUserMaxCapacitiesForAsset(
            address(supplier1),
            cUsdc
        );
        supplier1.borrow(cUsdc, toBorrow);

        positionsManager.setPauseStatus(cDai);
        positionsManager.setPauseStatus(cUsdc);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(cUsdc, 0);

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
        positionsManager.claimToTreasury(cDai);
    }
}
