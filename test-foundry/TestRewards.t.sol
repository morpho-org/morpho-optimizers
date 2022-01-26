// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/interfaces/aave/IAaveIncentivesController.sol";
import "./utils/TestSetup.sol";

import "hardhat/console.sol";

contract TestRewards is TestSetup {
    // Should claim the right amount of rewards
    function test_claim() public {
        uint256 toSupply = 100 * WAD;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        uint256 index = IAaveIncentivesController(aaveIncentivesControllerAddress)
        .assets(aDai)
        .index;
        uint256 balanceBefore = IERC20(wmatic).balanceOf(address(supplier1));
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserIndex(aDai, address(supplier1));
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        uint256 unclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );

        assertEq(index, userIndex);

        // here, unclaimed higher than expected
        assertEq(unclaimedRewards, 0);
        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);
        hevm.warp(block.timestamp + 365 days);
        positionsManager.claimRewards(aDaiInArray);
        index = IAaveIncentivesController(aaveIncentivesControllerAddress).assets(aDai).index;
        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 balanceAfter = IERC20(wmatic).balanceOf(address(supplier1));
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;
        assertEq(balanceAfter, expectedNewBalance);
    }

    // Anyone should be able to claim rewards on several markets one after another
    function test_claim_on_several_markets() public {
        uint256 toSupply = 100 * WAD;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = IERC20(wmatic).balanceOf(address(supplier1));

        hevm.warp(block.timestamp + 365 days);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        supplier1.claimRewards(aDaiInArray);
        uint256 rewardBalanceAfter1 = IERC20(wmatic).balanceOf(address(supplier1));
        assertGt(rewardBalanceAfter1, rewardBalanceBefore);

        address[] memory debtUsdcInArray = new address[](1);
        debtUsdcInArray[0] = variableDebtUsdc;
        supplier1.claimRewards(debtUsdcInArray);
        uint256 rewardBalanceAfter2 = IERC20(wmatic).balanceOf(address(supplier1));
        assertGt(rewardBalanceAfter2, rewardBalanceAfter1);
    }

    // Should not be possible to claim rewards for another asset
    function test_no_reward_on_other_market() public {
        uint256 toSupply = 100 * WAD;
        uint256 toSupply2 = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier2.approve(usdc, toSupply2);
        supplier2.supply(aUsdc, toSupply2);
        uint256 rewardBalanceBefore = IERC20(wmatic).balanceOf(address(supplier1));

        hevm.warp(block.timestamp + 365 days);

        address[] memory aUsdcInArray = new address[](1);
        aUsdcInArray[0] = aUsdc;
        supplier1.claimRewards(aUsdcInArray);
        uint256 rewardBalanceAfter = IERC20(wmatic).balanceOf(address(supplier1));
        assertEq(rewardBalanceAfter, rewardBalanceBefore);

        uint256 unclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            aUsdcInArray,
            address(supplier2)
        );
        assertGt(unclaimedRewards, 0);
    }

    // !! this one fails !!
    // Anyone should be able to claim rewards on several markets at once
    function test_claim_several_rewards_at_once() public {
        uint256 toSupply = 100 * WAD;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = IERC20(wmatic).balanceOf(address(supplier1));

        hevm.warp(block.timestamp + 365 days);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;

        uint256 unclaimedRewardsForDai = rewardsManager.accrueUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );

        uint256 allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        console.log("1");
        console.log("allUnclaimedRewards~~~", allUnclaimedRewards);
        console.log("unclaimedRewardsForDai", unclaimedRewardsForDai);
        assertGt(allUnclaimedRewards, unclaimedRewardsForDai);

        supplier1.claimRewards(tokensInArray);
        uint256 rewardBalanceAfter = IERC20(wmatic).balanceOf(address(supplier1));

        console.log("2");
        console.log("rewardBalanceAfter~", rewardBalanceAfter);
        console.log("rewardBalanceBefore", rewardBalanceBefore);
        assertGt(rewardBalanceAfter, rewardBalanceBefore);

        allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );

        console.log("3");
        console.log("allUnclaimedRewards", allUnclaimedRewards);
        assertEq(allUnclaimedRewards, 0);

        uint256 protocolUnclaimedRewards = IAaveIncentivesController(
            aaveIncentivesControllerAddress
        ).getRewardsBalance(tokensInArray, address(positionsManager));

        console.log("4");
        console.log("protocolUnclaimedRewards", protocolUnclaimedRewards);
        assertEq(protocolUnclaimedRewards, 0);
    }

    // Several users should claim their rewards independently
    function test_independant_claims() public {
        uint256 toSupply = 100 * WAD;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier2.approve(dai, toSupply);
        supplier3.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        supplier2.supply(aDai, toSupply);
        supplier2.borrow(aUsdc, toBorrow);
        supplier3.supply(aDai, toSupply);
        supplier3.borrow(aUsdc, toBorrow);
        uint256 balanceBefore1 = IERC20(wmatic).balanceOf(address(supplier1));
        uint256 balanceBefore2 = IERC20(wmatic).balanceOf(address(supplier2));
        uint256 balanceBefore3 = IERC20(wmatic).balanceOf(address(supplier3));

        hevm.warp(block.timestamp + 365 days);

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;
        supplier1.claimRewards(tokensInArray);
        supplier2.claimRewards(tokensInArray);
        supplier3.claimRewards(tokensInArray);
        uint256 balanceAfter1 = IERC20(wmatic).balanceOf(address(supplier1));
        uint256 balanceAfter2 = IERC20(wmatic).balanceOf(address(supplier2));
        uint256 balanceAfter3 = IERC20(wmatic).balanceOf(address(supplier3));

        assertGt(balanceAfter1, balanceBefore1);
        assertGt(balanceAfter2, balanceBefore2);
        assertGt(balanceAfter3, balanceBefore3);

        uint256 unclaimedRewards1 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        uint256 unclaimedRewards2 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier2)
        );
        uint256 unclaimedRewards3 = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier3)
        );
        assertEq(unclaimedRewards1, 0);
        assertEq(unclaimedRewards2, 0);
        assertEq(unclaimedRewards3, 0);

        uint256 protocolUnclaimedRewards = IAaveIncentivesController(
            aaveIncentivesControllerAddress
        ).getRewardsBalance(tokensInArray, address(positionsManager));
        assertEq(protocolUnclaimedRewards, 0);
    }
}
