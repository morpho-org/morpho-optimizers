// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRewardsManager is TestSetup {
    function testOnlyOwnerShouldBeAbleToSetAaveIncentivesController() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        rewardsManager.setAaveIncentivesController(address(1));

        rewardsManager.setAaveIncentivesController(address(1));
        assertEq(address(rewardsManager.aaveIncentivesController()), address(1));
    }

    function testOnlyOwnerShouldBeAbleToSetSwapManager() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        rewardsManager.setSwapManager(address(1));

        rewardsManager.setSwapManager(address(1));
        assertEq(address(rewardsManager.swapManager()), address(1));
    }
}
