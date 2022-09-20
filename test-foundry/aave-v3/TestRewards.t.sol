// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./setup/TestSetup.sol";

contract TestRewards is TestSetup {
    function testShouldRevertWhenClaimRewardsIsPaused() public {
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        morpho.setIsClaimRewardsPaused(true);

        hevm.expectRevert(abi.encodeWithSignature("ClaimRewardsPaused()"));
        morpho.claimRewards(aDaiInArray, false);
    }

    function testShouldClaimRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        uint256 balanceBefore = supplier1.balanceOf(rewardToken);

        (uint256 index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            aDai,
            rewardToken
        );

        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserAssetIndex(address(supplier1), aDai, rewardToken);
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        uint256 unclaimedRewards = rewardsManager.getUserAccruedRewards(
            aDaiInArray,
            address(supplier1),
            rewardToken
        );

        assertEq(userIndex, index, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        hevm.warp(block.timestamp + 365 days);
        supplier1.claimRewards(aDaiInArray, false);

        (index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            aDai,
            rewardToken
        );

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 balanceAfter = supplier1.balanceOf(rewardToken);
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;

        assertEq(balanceAfter, expectedNewBalance, "balance after wrong");
    }

    function testShouldGetRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        (uint256 index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            aDai,
            rewardToken
        );

        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserAssetIndex(address(supplier1), aDai, rewardToken);
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        uint256 unclaimedRewards = rewardsManager.getUserAccruedRewards(
            aDaiInArray,
            address(supplier1),
            rewardToken
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        hevm.warp(block.timestamp + 365 days);

        supplier1.withdraw(aDai, type(uint256).max);
        unclaimedRewards = rewardsManager.getUserAccruedRewards(
            aDaiInArray,
            address(supplier1),
            rewardToken
        );

        supplier1.claimRewards(aDaiInArray, false);

        (index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            aDai,
            rewardToken
        );

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e18;
        assertEq(unclaimedRewards, expectedClaimed);
    }

    function testShouldClaimRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, to6Decimals(50 ether));
        uint256 balanceBefore = supplier1.balanceOf(rewardToken);

        (uint256 index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            variableDebtUsdc,
            rewardToken
        );

        (, uint256 onPool) = morpho.borrowBalanceInOf(aUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.getUserAssetIndex(
            address(supplier1),
            variableDebtUsdc,
            rewardToken
        );
        address[] memory variableDebtUsdcArray = new address[](1);
        variableDebtUsdcArray[0] = variableDebtUsdc;
        uint256 unclaimedRewards = rewardsManager.getUserAccruedRewards(
            variableDebtUsdcArray,
            address(supplier1),
            rewardToken
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.warp(block.timestamp + 365 days);
        supplier1.claimRewards(variableDebtUsdcArray, false);

        (index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            variableDebtUsdc,
            rewardToken
        );

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e6;
        uint256 balanceAfter = supplier1.balanceOf(rewardToken);
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;

        assertEq(balanceAfter, expectedNewBalance, "balance after wrong");
    }

    function testShouldGetRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, to6Decimals(50 ether));

        (uint256 index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            variableDebtUsdc,
            rewardToken
        );

        (, uint256 onPool) = morpho.borrowBalanceInOf(aUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.getUserAssetIndex(
            address(supplier1),
            variableDebtUsdc,
            rewardToken
        );
        address[] memory variableDebtUsdcArray = new address[](1);
        variableDebtUsdcArray[0] = variableDebtUsdc;
        uint256 unclaimedRewards = rewardsManager.getUserAccruedRewards(
            variableDebtUsdcArray,
            address(supplier1),
            rewardToken
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.warp(block.timestamp + 365 days);

        supplier1.approve(usdc, type(uint256).max);
        supplier1.repay(aUsdc, type(uint256).max);
        unclaimedRewards = rewardsManager.getUserAccruedRewards(
            variableDebtUsdcArray,
            address(supplier1),
            rewardToken
        );

        supplier1.claimRewards(variableDebtUsdcArray, false);

        (index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            variableDebtUsdc,
            rewardToken
        );

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e6;
        assertEq(unclaimedRewards, expectedClaimed, "claimed");
    }

    function testShouldClaimOnSeveralMarkets() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(rewardToken);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        supplier1.claimRewards(aDaiInArray, false);
        uint256 rewardBalanceAfter1 = supplier1.balanceOf(rewardToken);
        assertGt(rewardBalanceAfter1, rewardBalanceBefore);

        address[] memory debtUsdcInArray = new address[](1);
        debtUsdcInArray[0] = variableDebtUsdc;
        supplier1.claimRewards(debtUsdcInArray, false);
        uint256 rewardBalanceAfter2 = supplier1.balanceOf(rewardToken);
        assertGt(rewardBalanceAfter2, rewardBalanceAfter1);
    }

    function testShouldNotBePossibleToClaimRewardsOnOtherMarket() public {
        uint256 toSupply1 = 100 ether;
        uint256 toSupply2 = 50 * 1e6;

        uint256 balanceBefore = supplier1.balanceOf(rewardToken);
        supplier1.approve(dai, toSupply1);
        supplier1.supply(aDai, toSupply1);

        supplier2.approve(usdc, toSupply2);
        supplier2.supply(aUsdc, toSupply2);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aUsdcInArray = new address[](1);
        aUsdcInArray[0] = aUsdc;
        (address[] memory rewardTokens, uint256[] memory claimedAmounts) = supplier1.claimRewards(
            aUsdcInArray,
            false
        );
        assertEq(rewardTokens.length, 1);
        assertEq(rewardTokens[0], rewardToken);
        assertEq(claimedAmounts.length, 1);
        assertEq(claimedAmounts[0], 0);

        uint256 balanceAfter = supplier1.balanceOf(rewardToken);
        assertEq(balanceAfter, balanceBefore);
    }

    function testShouldClaimRewardsOnSeveralMarketsAtOnce() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(rewardToken);

        hevm.warp(block.timestamp + 365 days);

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;

        supplier1.claimRewards(tokensInArray, false);
        uint256 rewardBalanceAfter = supplier1.balanceOf(rewardToken);

        assertGt(rewardBalanceAfter, rewardBalanceBefore);

        uint256 protocolUnclaimedRewards = IRewardsController(rewardsControllerAddress)
            .getUserRewards(tokensInArray, address(morpho), rewardToken);

        assertEq(protocolUnclaimedRewards, 0);
    }

    function testUsersShouldClaimRewardsIndependently() public {
        interactWithAave();
        interactWithMorpho();

        uint256[4] memory balanceBefore;
        balanceBefore[1] = IERC20(rewardToken).balanceOf(address(supplier1));
        balanceBefore[2] = IERC20(rewardToken).balanceOf(address(supplier2));
        balanceBefore[3] = IERC20(rewardToken).balanceOf(address(supplier3));

        hevm.warp(block.timestamp + 365 days);

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;
        supplier1.claimRewards(tokensInArray, false);
        supplier2.claimRewards(tokensInArray, false);
        supplier3.claimRewards(tokensInArray, false);

        uint256[4] memory balanceAfter;
        balanceAfter[1] = IERC20(rewardToken).balanceOf(address(supplier1));
        balanceAfter[2] = IERC20(rewardToken).balanceOf(address(supplier2));
        balanceAfter[3] = IERC20(rewardToken).balanceOf(address(supplier3));

        supplier1.aaveClaimRewards(tokensInArray);
        supplier2.aaveClaimRewards(tokensInArray);
        supplier3.aaveClaimRewards(tokensInArray);

        uint256[4] memory balanceAfterAave;
        balanceAfterAave[1] = IERC20(rewardToken).balanceOf(address(supplier1));
        balanceAfterAave[2] = IERC20(rewardToken).balanceOf(address(supplier2));
        balanceAfterAave[3] = IERC20(rewardToken).balanceOf(address(supplier3));

        uint256[4] memory claimedFromAave;
        claimedFromAave[1] = balanceAfterAave[1] - balanceAfter[1];
        claimedFromAave[2] = balanceAfterAave[2] - balanceAfter[2];
        claimedFromAave[3] = balanceAfterAave[3] - balanceAfter[3];

        uint256[4] memory claimedFromMorpho;
        claimedFromMorpho[1] = balanceAfter[1] - balanceBefore[1];
        claimedFromMorpho[2] = balanceAfter[2] - balanceBefore[2];
        claimedFromMorpho[3] = balanceAfter[3] - balanceBefore[3];
        testEqualityLarge(claimedFromAave[1], claimedFromMorpho[1], "claimed 1");
        testEqualityLarge(claimedFromAave[2], claimedFromMorpho[2], "claimed 2");
        testEqualityLarge(claimedFromAave[3], claimedFromMorpho[3], "claimed 3");

        assertGt(balanceAfter[1], balanceBefore[1]);
        assertGt(balanceAfter[2], balanceBefore[2]);
        assertGt(balanceAfter[3], balanceBefore[3]);

        uint256 unclaimedRewards1 = rewardsManager.getUserAccruedRewards(
            tokensInArray,
            address(supplier1),
            rewardToken
        );
        uint256 unclaimedRewards2 = rewardsManager.getUserAccruedRewards(
            tokensInArray,
            address(supplier2),
            rewardToken
        );
        uint256 unclaimedRewards3 = rewardsManager.getUserAccruedRewards(
            tokensInArray,
            address(supplier3),
            rewardToken
        );

        assertEq(unclaimedRewards1, 0);
        assertEq(unclaimedRewards2, 0);
        assertEq(unclaimedRewards3, 0);

        uint256 protocolUnclaimedRewards = IRewardsController(rewardsControllerAddress)
            .getUserRewards(tokensInArray, address(morpho), rewardToken);

        assertApproxEqAbs(protocolUnclaimedRewards, 0, 2);
    }

    function interactWithAave() internal {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;

        supplier1.aaveSupply(dai, toSupply);
        supplier1.aaveBorrow(usdc, toBorrow);
        supplier2.aaveSupply(dai, toSupply);
        supplier2.aaveBorrow(usdc, toBorrow);
        supplier3.aaveSupply(dai, toSupply);
        supplier3.aaveBorrow(usdc, toBorrow);
    }

    function interactWithMorpho() internal {
        uint256 toSupply = 100 ether;
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
    }

    function testShouldClaimRewardsAndTradeForMorpkoTokens() public {
        // 10% bonus.
        incentivesVault.setBonus(1_000);

        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserAssetIndex(address(supplier1), aDai, rewardToken);
        uint256 rewardBalanceBefore = supplier1.balanceOf(rewardToken);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        hevm.warp(block.timestamp + 365 days);
        supplier1.claimRewards(aDaiInArray, true);

        (uint256 index, , , ) = IRewardsController(rewardsControllerAddress).getRewardsData(
            aDai,
            rewardToken
        );

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 expectedMorphoTokens = (expectedClaimed * 11_000) / 10_000; // 10% bonus with a dumb oracle 1:1 exchange from COMP to MORPHO.

        uint256 morphoBalance = supplier1.balanceOf(address(morphoToken));
        uint256 rewardBalanceAfter = supplier1.balanceOf(rewardToken);
        testEquality(morphoBalance, expectedMorphoTokens, "expected Morpho balance");
        testEquality(rewardBalanceBefore, rewardBalanceAfter, "expected reward balance");
    }

    function testFailShouldNotClaimRewardsWhenRewardsManagerIsAddressZero() public {
        uint256 amount = 1 ether;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(aUsdc, to6Decimals(amount));

        // Set RewardsManager to address(0).
        morpho.setRewardsManager(IRewardsManager(address(0)));

        move1YearForward(aUsdc);

        address[] memory markets = new address[](1);
        markets[0] = aUsdc;

        // User tries to claim its rewards on Morpho.
        supplier1.claimRewards(markets, false);
    }
}
