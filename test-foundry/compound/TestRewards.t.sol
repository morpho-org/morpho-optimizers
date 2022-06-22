// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRewards is TestSetup {
    function testShouldRevertClaimingZero() public {
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;

        hevm.expectRevert(MorphoGovernance.AmountIsZero.selector);
        morpho.claimRewards(cTokens, false);
    }

    function testShouldClaimRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        uint256 balanceBefore = supplier1.balanceOf(comp);

        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        uint256 userIndex = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;
        uint256 unclaimedRewards = lens.getUserUnclaimedRewards(cTokens, address(supplier1));

        uint256 index = comptroller.compSupplyState(cDai).index;

        testEquality(userIndex, index, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        hevm.roll(block.number + 1_000);
        supplier1.claimRewards(cTokens, false);

        index = comptroller.compSupplyState(cDai).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        uint256 balanceAfter = supplier1.balanceOf(comp);
        uint256 expectedNewBalance = expectedClaimed + balanceBefore;

        testEquality(balanceAfter, expectedNewBalance, "balance after wrong");
    }

    function testShouldRevertWhenClaimRewardsIsPaused() public {
        address[] memory cDaiInArray = new address[](1);
        cDaiInArray[0] = cDai;

        morpho.setPauseStatusClaimRewards(true);

        hevm.expectRevert(abi.encodeWithSignature("ClaimRewardsPaused()"));
        morpho.claimRewards(cDaiInArray, false);
    }

    function testShouldGetRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        uint256 index = comptroller.compSupplyState(cDai).index;

        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        uint256 userIndex = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;
        uint256 unclaimedRewards = lens.getUserUnclaimedRewards(cTokens, address(supplier1));

        testEquality(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        hevm.roll(block.number + 1_000);
        unclaimedRewards = lens.getUserUnclaimedRewards(cTokens, address(supplier1));

        supplier1.claimRewards(cTokens, false);
        index = comptroller.compSupplyState(cDai).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        testEquality(unclaimedRewards, expectedClaimed);
    }

    function testShouldClaimRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, to6Decimals(50 ether));

        uint256 index = comptroller.compBorrowState(cUsdc).index;

        (, uint256 onPool) = morpho.borrowBalanceInOf(cUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.compBorrowerIndex(cUsdc, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cUsdc;
        hevm.prank(address(morpho));
        uint256 unclaimedRewards = rewardsManager.claimRewards(cTokens, address(supplier1));

        testEquality(userIndex, index, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.roll(block.number + 1_000);
        supplier1.claimRewards(cTokens, false);

        index = comptroller.compBorrowState(cUsdc).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        uint256 balanceAfter = supplier1.balanceOf(comp);

        testEquality(balanceAfter, expectedClaimed, "balance after wrong");
    }

    function testShouldGetRightAmountOfBorrowRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, to6Decimals(50 ether));

        uint256 index = comptroller.compBorrowState(cUsdc).index;

        (, uint256 onPool) = morpho.borrowBalanceInOf(cUsdc, address(supplier1));
        uint256 userIndex = rewardsManager.compBorrowerIndex(cUsdc, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cUsdc;
        uint256 unclaimedRewards = lens.getUserUnclaimedRewards(cTokens, address(supplier1));

        testEquality(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.roll(block.number + 1_000);

        unclaimedRewards = lens.getUserUnclaimedRewards(cTokens, address(supplier1));

        supplier1.claimRewards(cTokens, false);
        index = comptroller.compBorrowState(cUsdc).index;

        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        testEquality(unclaimedRewards, expectedClaimed);
    }

    function testShouldClaimOnSeveralMarkets() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, toBorrow);
        uint256 rewardBalanceBefore = supplier1.balanceOf(comp);

        hevm.roll(block.number + 1_000);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;
        supplier1.claimRewards(cTokens, false);
        uint256 rewardBalanceAfter1 = supplier1.balanceOf(comp);
        assertGt(rewardBalanceAfter1, rewardBalanceBefore);

        address[] memory debtUsdcInArray = new address[](1);
        debtUsdcInArray[0] = cUsdc;
        supplier1.claimRewards(debtUsdcInArray, false);
        uint256 rewardBalanceAfter2 = supplier1.balanceOf(comp);
        assertGt(rewardBalanceAfter2, rewardBalanceAfter1);
    }

    function testShouldNotBePossibleToClaimRewardsOnOtherMarket() public {
        uint256 toSupply = 100 ether;
        uint256 toSupply2 = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier2.approve(usdc, toSupply2);
        supplier2.supply(cUsdc, toSupply2);

        hevm.roll(block.number + 1_000);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cUsdc;

        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        supplier1.claimRewards(cTokens, false);
    }

    function testShouldClaimRewardsOnSeveralMarketsAtOnce() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;
        supplier1.approve(dai, toSupply);
        supplier1.approve(wEth, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.supply(cEth, toSupply);
        supplier1.borrow(cUsdc, toBorrow);

        hevm.roll(block.number + 1_000_000);

        address[] memory daiInArray = new address[](1);
        daiInArray[0] = cDai;

        address[] memory tokensInArray = new address[](3);
        tokensInArray[0] = cDai;
        tokensInArray[1] = cEth;
        tokensInArray[2] = cUsdc;

        uint256 unclaimedRewardsForDaiView = lens.getUserUnclaimedRewards(
            daiInArray,
            address(supplier1)
        );
        assertGt(unclaimedRewardsForDaiView, 0);

        uint256 allUnclaimedRewardsView = lens.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        assertGt(allUnclaimedRewardsView, 0);

        hevm.prank(address(morpho));
        uint256 allUnclaimedRewards = rewardsManager.claimRewards(
            tokensInArray,
            address(supplier1)
        );
        assertEq(allUnclaimedRewards, allUnclaimedRewards, "wrong rewards amount");

        allUnclaimedRewardsView = lens.getUserUnclaimedRewards(tokensInArray, address(supplier1));
        assertEq(allUnclaimedRewardsView, 0, "unclaimed rewards not null");

        hevm.prank(address(morpho));
        allUnclaimedRewards = rewardsManager.claimRewards(tokensInArray, address(supplier1));
        assertEq(allUnclaimedRewards, 0);
    }

    // TODO: investigate why this test fails.
    function _testUsersShouldClaimRewardsIndependently() public {
        interactWithCompound();
        interactWithMorpho();

        uint256[4] memory balanceBefore;
        balanceBefore[1] = ERC20(comp).balanceOf(address(supplier1));
        balanceBefore[2] = ERC20(comp).balanceOf(address(supplier2));
        balanceBefore[3] = ERC20(comp).balanceOf(address(supplier3));

        hevm.roll(block.number + 1_000);

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = cDai;
        tokensInArray[1] = cUsdc;
        supplier1.claimRewards(tokensInArray, false);
        supplier2.claimRewards(tokensInArray, false);
        supplier3.claimRewards(tokensInArray, false);

        uint256[4] memory balanceAfter;
        balanceAfter[1] = ERC20(comp).balanceOf(address(supplier1));
        balanceAfter[2] = ERC20(comp).balanceOf(address(supplier2));
        balanceAfter[3] = ERC20(comp).balanceOf(address(supplier3));

        supplier1.compoundClaimRewards(tokensInArray);
        supplier2.compoundClaimRewards(tokensInArray);
        supplier3.compoundClaimRewards(tokensInArray);

        uint256[4] memory balanceAfterCompound;
        balanceAfterCompound[1] = ERC20(comp).balanceOf(address(supplier1));
        balanceAfterCompound[2] = ERC20(comp).balanceOf(address(supplier2));
        balanceAfterCompound[3] = ERC20(comp).balanceOf(address(supplier3));

        uint256[4] memory claimedFromCompound;
        claimedFromCompound[1] = balanceAfterCompound[1] - balanceAfter[1];
        claimedFromCompound[2] = balanceAfterCompound[2] - balanceAfter[2];
        claimedFromCompound[3] = balanceAfterCompound[3] - balanceAfter[3];

        uint256[4] memory claimedFromMorpho;
        claimedFromMorpho[1] = balanceAfter[1];
        claimedFromMorpho[2] = balanceAfter[2];
        claimedFromMorpho[3] = balanceAfter[3];
        testEquality(claimedFromCompound[1], claimedFromMorpho[1], "claimed rewards 1");
        testEquality(claimedFromCompound[2], claimedFromMorpho[2], "claimed rewards 2");
        testEquality(claimedFromCompound[3], claimedFromMorpho[3], "claimed rewards 3");

        assertGt(balanceAfter[1], balanceBefore[1]);
        assertGt(balanceAfter[2], balanceBefore[2]);
        assertGt(balanceAfter[3], balanceBefore[3]);

        hevm.prank(address(morpho));
        uint256 unclaimedRewards1 = rewardsManager.claimRewards(tokensInArray, address(supplier1));
        uint256 unclaimedRewards2 = rewardsManager.claimRewards(tokensInArray, address(supplier2));
        uint256 unclaimedRewards3 = rewardsManager.claimRewards(tokensInArray, address(supplier3));

        assertEq(unclaimedRewards1, 0);
        assertEq(unclaimedRewards2, 0);
        assertEq(unclaimedRewards3, 0);
    }

    function interactWithCompound() internal {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;

        supplier1.compoundSupply(cDai, toSupply);
        supplier1.compoundBorrow(cUsdc, toBorrow);
        supplier2.compoundSupply(cDai, toSupply);
        supplier2.compoundBorrow(cUsdc, toBorrow);
        supplier3.compoundSupply(cDai, toSupply);
        supplier3.compoundBorrow(cUsdc, toBorrow);
    }

    function interactWithMorpho() internal {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = 50 * 1e6;

        supplier1.approve(dai, toSupply);
        supplier2.approve(dai, toSupply);
        supplier3.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, toBorrow);
        supplier2.supply(cDai, toSupply);
        supplier2.borrow(cUsdc, toBorrow);
        supplier3.supply(cDai, toSupply);
        supplier3.borrow(cUsdc, toBorrow);
    }

    function testShouldClaimRewardsAndTradeForMorpkoTokens() public {
        // 10% bonus.
        incentivesVault.setBonus(1_000);

        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        uint256 userIndex = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        uint256 rewardBalanceBefore = supplier1.balanceOf(comp);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;

        hevm.roll(block.number + 1_000);
        supplier1.claimRewards(cTokens, true);

        uint256 index = comptroller.compSupplyState(cDai).index;
        uint256 expectedClaimed = (onPool * (index - userIndex)) / 1e36;
        uint256 expectedMorphoTokens = (expectedClaimed * 11_000) / 10_000; // 10% bonus with a dumb oracle 1:1 exchange from COMP to MORPHO.

        uint256 morphoBalance = supplier1.balanceOf(address(morphoToken));
        uint256 rewardBalanceAfter = supplier1.balanceOf(comp);
        testEquality(morphoBalance, expectedMorphoTokens);
        testEquality(rewardBalanceBefore, rewardBalanceAfter);
    }

    function testShouldClaimTheSameAmountOfRewards() public {
        uint256 smallAmount = 1 ether;
        uint256 bigAmount = 10_000 ether;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(cUsdc, to6Decimals(smallAmount));
        supplier2.approve(usdc, type(uint256).max);
        supplier2.supply(cUsdc, to6Decimals(smallAmount));

        move1000BlocksForward(cUsdc);

        address[] memory markets = new address[](1);
        markets[0] = cUsdc;

        hevm.prank(address(morpho));
        rewardsManager.claimRewards(markets, address(supplier1));

        // supplier2 tries to game the system by supplying a huge amount of tokens and withdrawing right after accruing its rewards.
        supplier2.supply(cUsdc, to6Decimals(bigAmount));
        hevm.prank(address(morpho));
        rewardsManager.claimRewards(markets, address(supplier2));
        supplier2.withdraw(cUsdc, to6Decimals(bigAmount));

        assertEq(
            lens.getUserUnclaimedRewards(markets, address(supplier1)),
            lens.getUserUnclaimedRewards(markets, address(supplier2))
        );
    }

    function testFailShouldNotClaimRewardsWhenRewardsManagerIsAddressZero() public {
        uint256 amount = 1 ether;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(cUsdc, to6Decimals(amount));

        // Set RewardsManager to address(0).
        morpho.setRewardsManager(IRewardsManager(address(0)));

        move1000BlocksForward(cUsdc);

        address[] memory markets = new address[](1);
        markets[0] = cUsdc;

        // User accrues its rewards.
        hevm.prank(address(morpho));
        rewardsManager.claimRewards(markets, address(supplier1));

        // User tries to claim its rewards on Morpho.
        supplier1.claimRewards(markets, false);
    }

    function testShouldUpdateCorrectSupplyIndex() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);

        hevm.roll(block.number + 5_000);
        supplier1.approve(dai, cDai, type(uint256).max);
        supplier1.compoundSupply(cDai, amount);
        hevm.roll(block.number + 5_000);

        supplier1.borrow(cDai, amount / 2);

        uint256 userIndexAfter = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        IComptroller.CompMarketState memory compoundAfter = comptroller.compSupplyState(cDai);

        assertEq(userIndexAfter, compoundAfter.index);
    }

    function testShouldUpdateCorrectSupplyIndexWhenSpeedIs0() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);

        hevm.roll(block.number + 1);
        hevm.prank(comptroller.admin());
        ICToken[] memory cTokens = new ICToken[](1);
        uint256[] memory supplySpeeds = new uint256[](1);
        uint256[] memory borrowSpeeds = new uint256[](1);
        cTokens[0] = ICToken(cDai);
        comptroller._setCompSpeeds(cTokens, supplySpeeds, borrowSpeeds);
        hevm.roll(block.number + 1);

        supplier1.borrow(cDai, amount / 2);

        uint256 userIndexAfter = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        IComptroller.CompMarketState memory compoundAfter = comptroller.compSupplyState(cDai);

        assertEq(userIndexAfter, compoundAfter.index);
    }

    function testShouldUpdateCorrectBorrowIndex() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, type(uint256).max);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 5_000);
        borrower1.approve(dai, cDai, type(uint256).max);
        borrower1.compoundSupply(cDai, amount);
        borrower1.compoundBorrow(cDai, amount / 2);
        hevm.roll(block.number + 5_000);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, amount / 2);

        uint256 userIndexAfter = rewardsManager.compBorrowerIndex(cDai, address(borrower1));
        IComptroller.CompMarketState memory compoundAfter = comptroller.compBorrowState(cDai);

        assertEq(userIndexAfter, compoundAfter.index);
    }

    function testShouldUpdateCorrectBorrowIndexWhenSpeedIs0() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, type(uint256).max);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 1);
        hevm.prank(comptroller.admin());
        ICToken[] memory cTokens = new ICToken[](1);
        uint256[] memory supplySpeeds = new uint256[](1);
        uint256[] memory borrowSpeeds = new uint256[](1);
        cTokens[0] = ICToken(cDai);
        comptroller._setCompSpeeds(cTokens, supplySpeeds, borrowSpeeds);
        hevm.roll(block.number + 1);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, amount / 2);

        uint256 userIndexAfter = rewardsManager.compBorrowerIndex(cDai, address(borrower1));
        IComptroller.CompMarketState memory compoundAfter = comptroller.compBorrowState(cDai);

        assertEq(userIndexAfter, compoundAfter.index);
    }

    function testShouldComputeCorrectSupplyIndex() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);

        hevm.roll(block.number + 5_000);
        supplier1.approve(dai, cDai, type(uint256).max);
        supplier1.compoundSupply(cDai, amount);
        hevm.roll(block.number + 5_000);

        uint256 updatedIndex = lens.getUpdatedCompSupplyIndex(cDai);

        supplier1.compoundSupply(cDai, amount / 10); // Update compSupplyState.
        IComptroller.CompMarketState memory compoundAfter = comptroller.compSupplyState(cDai);

        assertEq(updatedIndex, compoundAfter.index);
    }

    function testShouldComputeCorrectBorrowIndex() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, type(uint256).max);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 5_000);
        borrower1.approve(dai, cDai, type(uint256).max);
        borrower1.compoundSupply(cDai, amount);
        borrower1.compoundBorrow(cDai, amount / 2);
        hevm.roll(block.number + 5_000);

        ICToken(cDai).accrueInterest();
        uint256 updatedIndex = lens.getUpdatedCompBorrowIndex(cDai);

        borrower1.compoundBorrow(cDai, amount / 10); // Update compBorrowState.
        IComptroller.CompMarketState memory compoundAfter = comptroller.compBorrowState(cDai);

        assertEq(updatedIndex, compoundAfter.index);
    }
}
