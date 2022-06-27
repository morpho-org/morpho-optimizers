// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRewards is TestSetup {
    function testShouldRevertClaimingZero() public {
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        morpho.claimRewards(aDaiInArray, false);
    }

    function testShouldRevertWhenClaimRewardsIsPaused() public {
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        morpho.setClaimRewardsPauseStatus(true);

        hevm.expectRevert(abi.encodeWithSignature("ClaimRewardsPaused()"));
        morpho.claimRewards(aDaiInArray, false);
    }

    function testShouldClaimRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        uint256 balanceBefore = supplier1.balanceOf(REWARD_TOKEN);
        uint256 index;

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                aDai
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(aDai);
            index = assetData.index;
        }

        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserIndex(aDai, address(supplier1));
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        hevm.warp(block.timestamp + 365 days);
        supplier1.claimRewards(aDaiInArray, false);

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                aDai
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(aDai);
            index = assetData.index;
        }

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 balanceAfter = supplier1.balanceOf(REWARD_TOKEN);
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;

        assertEq(balanceAfter, expectedNewBalance, "balance after wrong");
    }

    function testShouldGetRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        uint256 index;

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                aDai
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(aDai);
            index = assetData.index;
        }

        (, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        uint256 userIndex = rewardsManager.getUserIndex(aDai, address(supplier1));
        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        hevm.warp(block.timestamp + 365 days);
        unclaimedRewards = rewardsManager.getUserUnclaimedRewards(aDaiInArray, address(supplier1));

        supplier1.claimRewards(aDaiInArray, false);
        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                aDai
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(aDai);
            index = assetData.index;
        }

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        assertEq(unclaimedRewards, expectedClaimed);
    }

    function testShouldClaimRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, to6Decimals(50 ether));
        uint256 balanceBefore = supplier1.balanceOf(REWARD_TOKEN);
        uint256 index;

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                variableDebtUsdc
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(variableDebtUsdc);
            index = assetData.index;
        }

        (, uint256 onPool) = morpho.borrowBalanceInOf(aUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.getUserIndex(variableDebtUsdc, address(supplier1));
        address[] memory variableDebtUsdcArray = new address[](1);
        variableDebtUsdcArray[0] = variableDebtUsdc;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            variableDebtUsdcArray,
            address(supplier1)
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.warp(block.timestamp + 365 days);
        supplier1.claimRewards(variableDebtUsdcArray, false);

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                variableDebtUsdc
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(variableDebtUsdc);
            index = assetData.index;
        }

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 balanceAfter = supplier1.balanceOf(REWARD_TOKEN);
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;

        assertEq(balanceAfter, expectedNewBalance, "balance after wrong");
    }

    function testShouldGetRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, to6Decimals(50 ether));
        uint256 index;

        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                variableDebtUsdc
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(variableDebtUsdc);
            index = assetData.index;
        }

        (, uint256 onPool) = morpho.borrowBalanceInOf(aUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.getUserIndex(variableDebtUsdc, address(supplier1));
        address[] memory variableDebtUsdcArray = new address[](1);
        variableDebtUsdcArray[0] = variableDebtUsdc;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            variableDebtUsdcArray,
            address(supplier1)
        );

        assertEq(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.warp(block.timestamp + 365 days);
        unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            variableDebtUsdcArray,
            address(supplier1)
        );

        supplier1.claimRewards(variableDebtUsdcArray, false);
        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                variableDebtUsdc
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(variableDebtUsdc);
            index = assetData.index;
        }

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        assertEq(unclaimedRewards, expectedClaimed);
    }

    function testShouldClaimOnSeveralMarkets() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(REWARD_TOKEN);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;
        supplier1.claimRewards(aDaiInArray, false);
        uint256 rewardBalanceAfter1 = supplier1.balanceOf(REWARD_TOKEN);
        assertGt(rewardBalanceAfter1, rewardBalanceBefore);

        address[] memory debtUsdcInArray = new address[](1);
        debtUsdcInArray[0] = variableDebtUsdc;
        supplier1.claimRewards(debtUsdcInArray, false);
        uint256 rewardBalanceAfter2 = supplier1.balanceOf(REWARD_TOKEN);
        assertGt(rewardBalanceAfter2, rewardBalanceAfter1);
    }

    function testShouldNotBePossibleToClaimRewardsOnOtherMarket() public {
        uint256 toSupply = 100 ether;
        uint256 toSupply2 = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier2.approve(usdc, toSupply2);
        supplier2.supply(aUsdc, toSupply2);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aUsdcInArray = new address[](1);
        aUsdcInArray[0] = aUsdc;

        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        supplier1.claimRewards(aUsdcInArray, false);
    }

    function testShouldClaimRewardsOnSeveralMarketsAtOnce() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(REWARD_TOKEN);

        hevm.warp(block.timestamp + 365 days);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;

        uint256 unclaimedRewardsForDaiView = rewardsManager.getUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );
        uint256 unclaimedRewardsForDai = rewardsManager.getUserUnclaimedRewards(
            aDaiInArray,
            address(supplier1)
        );
        assertEq(unclaimedRewardsForDaiView, unclaimedRewardsForDai);

        uint256 allUnclaimedRewardsView = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        uint256 allUnclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        assertEq(allUnclaimedRewardsView, allUnclaimedRewards);
        assertGt(allUnclaimedRewards, unclaimedRewardsForDai);

        supplier1.claimRewards(tokensInArray, false);
        uint256 rewardBalanceAfter = supplier1.balanceOf(REWARD_TOKEN);

        assertGt(rewardBalanceAfter, rewardBalanceBefore);

        allUnclaimedRewardsView = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        allUnclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        assertEq(allUnclaimedRewardsView, allUnclaimedRewards);
        assertEq(allUnclaimedRewards, 0);

        uint256 protocolUnclaimedRewards = IAaveIncentivesController(
            aaveIncentivesControllerAddress
        ).getRewardsBalance(tokensInArray, address(morpho));

        assertEq(protocolUnclaimedRewards, 0);
    }

    function testUsersShouldClaimRewardsIndependently() public {
        interactWithAave();
        interactWithMorpho();

        uint256[4] memory balanceBefore;
        balanceBefore[1] = IERC20(REWARD_TOKEN).balanceOf(address(supplier1));
        balanceBefore[2] = IERC20(REWARD_TOKEN).balanceOf(address(supplier2));
        balanceBefore[3] = IERC20(REWARD_TOKEN).balanceOf(address(supplier3));

        hevm.warp(block.timestamp + 365 days);

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = aDai;
        tokensInArray[1] = variableDebtUsdc;
        supplier1.claimRewards(tokensInArray, false);
        supplier2.claimRewards(tokensInArray, false);
        supplier3.claimRewards(tokensInArray, false);

        uint256[4] memory balanceAfter;
        balanceAfter[1] = IERC20(REWARD_TOKEN).balanceOf(address(supplier1));
        balanceAfter[2] = IERC20(REWARD_TOKEN).balanceOf(address(supplier2));
        balanceAfter[3] = IERC20(REWARD_TOKEN).balanceOf(address(supplier3));

        supplier1.aaveClaimRewards(tokensInArray);
        supplier2.aaveClaimRewards(tokensInArray);
        supplier3.aaveClaimRewards(tokensInArray);

        uint256[4] memory balanceAfterAave;
        balanceAfterAave[1] = IERC20(REWARD_TOKEN).balanceOf(address(supplier1));
        balanceAfterAave[2] = IERC20(REWARD_TOKEN).balanceOf(address(supplier2));
        balanceAfterAave[3] = IERC20(REWARD_TOKEN).balanceOf(address(supplier3));

        uint256[4] memory claimedFromAave;
        claimedFromAave[1] = balanceAfterAave[1] - balanceAfter[1];
        claimedFromAave[2] = balanceAfterAave[2] - balanceAfter[2];
        claimedFromAave[3] = balanceAfterAave[3] - balanceAfter[3];

        uint256[4] memory claimedFromMorpho;
        claimedFromMorpho[1] = balanceAfter[1] - balanceBefore[1];
        claimedFromMorpho[2] = balanceAfter[2] - balanceBefore[2];
        claimedFromMorpho[3] = balanceAfter[3] - balanceBefore[3];
        assertEq(claimedFromAave[1], claimedFromMorpho[1]);
        assertEq(claimedFromAave[2], claimedFromMorpho[2]);
        assertEq(claimedFromAave[3], claimedFromMorpho[3]);

        assertGt(balanceAfter[1], balanceBefore[1]);
        assertGt(balanceAfter[2], balanceBefore[2]);
        assertGt(balanceAfter[3], balanceBefore[3]);

        uint256 unclaimedRewards1 = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        uint256 unclaimedRewards2 = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier2)
        );
        uint256 unclaimedRewards3 = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier3)
        );

        assertEq(unclaimedRewards1, 0);
        assertEq(unclaimedRewards2, 0);
        assertEq(unclaimedRewards3, 0);

        uint256 protocolUnclaimedRewards = IAaveIncentivesController(
            aaveIncentivesControllerAddress
        ).getRewardsBalance(tokensInArray, address(morpho));

        assertApproxEqAbs(protocolUnclaimedRewards, 0, 5);
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
        uint256 userIndex = rewardsManager.getUserIndex(aDai, address(supplier1));
        uint256 rewardBalanceBefore = supplier1.balanceOf(REWARD_TOKEN);

        address[] memory aDaiInArray = new address[](1);
        aDaiInArray[0] = aDai;

        hevm.warp(block.timestamp + 365 days);
        supplier1.claimRewards(aDaiInArray, true);

        uint256 index;
        if (block.chainid == Chains.AVALANCHE_MAINNET || block.chainid == Chains.ETH_MAINNET) {
            (index, , ) = IAaveIncentivesController(aaveIncentivesControllerAddress).getAssetData(
                aDai
            );
        } else {
            // Polygon network
            IAaveIncentivesController.AssetData memory assetData = IAaveIncentivesController(
                aaveIncentivesControllerAddress
            ).assets(aDai);
            index = assetData.index;
        }

        uint256 expectedClaimed = (onPool * (index - userIndex)) / WAD;
        uint256 expectedMorphoTokens = (expectedClaimed * 11_000) / 10_000; // 10% bonus with a dumb oracle 1:1 exchange from COMP to MORPHO.

        uint256 morphoBalance = supplier1.balanceOf(address(morphoToken));
        uint256 rewardBalanceAfter = supplier1.balanceOf(REWARD_TOKEN);
        testEquality(morphoBalance, expectedMorphoTokens, "expected Morpho balance");
        testEquality(rewardBalanceBefore, rewardBalanceAfter, "expected reward balance");
    }

    function testShouldClaimTheSameAmountOfRewards() public {
        uint256 smallAmount = 1 ether;
        uint256 bigAmount = 10_000 ether;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(aUsdc, to6Decimals(smallAmount));
        supplier2.approve(usdc, type(uint256).max);
        supplier2.supply(aUsdc, to6Decimals(smallAmount));

        move1YearForward(aUsdc);

        address[] memory markets = new address[](1);
        markets[0] = aUsdc;

        uint256 unclaimedRewards1 = rewardsManager.getUserUnclaimedRewards(
            markets,
            address(supplier1)
        );

        // supplier2 tries to game the system by supplying a huge amount of tokens and withdrawing right after accruing its rewards.
        supplier2.supply(aUsdc, to6Decimals(bigAmount));
        uint256 unclaimedRewards2 = rewardsManager.getUserUnclaimedRewards(
            markets,
            address(supplier2)
        );
        supplier2.withdraw(aUsdc, to6Decimals(bigAmount));

        assertEq(unclaimedRewards1, unclaimedRewards2);
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
