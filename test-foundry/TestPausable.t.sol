// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestPausable is TestSetup {
    function test_setup() public {
        assertFalse(positionsManager.paused(), "paused is true");
    }

    function test_only_markets_owner_can_trigger_pause_function() public {
        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManagerOwner()"));
        supplier1.setPauseStatus();

        positionsManager.setPauseStatus();
        assertTrue(positionsManager.paused(), "paused is false");
    }

    function test_pause_unpause() public {
        positionsManager.setPauseStatus();
        assertTrue(positionsManager.paused(), "paused is false");

        positionsManager.setPauseStatus();
        assertFalse(positionsManager.paused(), "paused is true");
    }

    function test_ability_to_trigger_functions_when_not_paused() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.approve(usdc, toBorrow);

        supplier1.supply(aDai, amount);
        supplier1.borrow(aUsdc, toBorrow);
        supplier1.repay(aUsdc, toBorrow);
        supplier1.withdraw(aDai, amount);

        // Liquidate should pass whenNotPaused() modifier
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        supplier1.liquidate(aUsdc, aDai, address(supplier1), 0);

        address[] memory assets = new address[](1);
        assets[0] = aDai;
        supplier1.claimRewards(assets);

        positionsManager.claimToTreasury(aDai);
    }

    function test_not_possible_to_trigger_functions_when_paused() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        positionsManager.setPauseStatus();

        supplier1.approve(dai, amount);
        supplier1.approve(usdc, toBorrow);

        hevm.expectRevert("Pausable: paused");
        supplier1.supply(aDai, amount);
        hevm.expectRevert("Pausable: paused");
        supplier1.borrow(aUsdc, toBorrow);
        hevm.expectRevert("Pausable: paused");
        supplier1.repay(aUsdc, toBorrow);
        hevm.expectRevert("Pausable: paused");
        supplier1.withdraw(aDai, amount);

        hevm.expectRevert("Pausable: paused");
        supplier1.liquidate(aUsdc, aDai, address(supplier1), 0);

        address[] memory assets = new address[](1);
        assets[0] = aDai;
        hevm.expectRevert("Pausable: paused");
        supplier1.claimRewards(assets);

        hevm.expectRevert("Pausable: paused");
        positionsManager.claimToTreasury(aDai);
    }
}
