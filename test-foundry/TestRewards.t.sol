// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/interfaces/aave/IAaveIncentivesController.sol";
import "./utils/TestSetup.sol";

contract TestRewards is TestSetup {
    // Should claim the right amount of rewards
    function test_claim() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);

        uint256 index = IAaveIncentivesController(aaveIncentivesControllerAddress)
        .assets(aDai)
        .index;
        uint256 balanceBefore = IERC20(wmatic).balanceOf(address(supplier1));
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserIndex(aDai, address(supplier1));
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );
        assertEq(index, userIndex);
        assertEq(unclaimedRewards, 0);
        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);
        hevm.warp(block.timestamp + 365 days); // todo : should we actually change basing on blocs ?
        positionsManager.claimRewards(aDaiInArray);
        index = IAaveIncentivesController(aaveIncentivesControllerAddress).assets(aDai).index;
        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 balanceAfter = IERC20(wmatic).balanceOf(address(supplier1));
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;
        assertEq(balanceAfter, expectedNewBalance);
    }
}
