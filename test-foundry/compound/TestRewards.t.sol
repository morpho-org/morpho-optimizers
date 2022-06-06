// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRewards is TestSetup {
    function testShouldRevertClaimingZero() public {
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;

        hevm.expectRevert(MorphoGovernance.AmountIsZero.selector);
        morpho.claimRewards(cTokens, false);
    }

    function testShouldRevertWhenAccruingRewardsForInvalidCToken() public {
        address[] memory cTokens = new address[](2);
        cTokens[0] = cDai;
        cTokens[1] = dai;

        hevm.expectRevert(RewardsManager.InvalidCToken.selector);
        rewardsManager.accrueUserUnclaimedRewards(cTokens, address(supplier1));
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
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

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

    function testShouldGetRightAmountOfSupplyRewards() public {
        uint256 toSupply = 100 ether;
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        uint256 index = comptroller.compSupplyState(cDai).index;

        (, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        uint256 userIndex = rewardsManager.compSupplierIndex(cDai, address(supplier1));
        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

        testEquality(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        hevm.roll(block.number + 1_000);
        unclaimedRewards = rewardsManager.getUserUnclaimedRewards(cTokens, address(supplier1));

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
        uint256 unclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

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
        uint256 unclaimedRewards = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );

        testEquality(index, userIndex, "user index wrong");
        assertEq(unclaimedRewards, 0, "unclaimed rewards should be 0");

        hevm.roll(block.number + 1_000);

        unclaimedRewards = rewardsManager.getUserUnclaimedRewards(cTokens, address(supplier1));

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
        supplier1.supply(cDai, toSupply);
        supplier1.borrow(cUsdc, toBorrow);

        hevm.roll(block.number + 1_000);

        address[] memory cTokens = new address[](1);
        cTokens[0] = cDai;

        address[] memory tokensInArray = new address[](2);
        tokensInArray[0] = cDai;
        tokensInArray[1] = cUsdc;

        uint256 unclaimedRewardsForDaiView = rewardsManager.getUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );
        uint256 unclaimedRewardsForDai = rewardsManager.accrueUserUnclaimedRewards(
            cTokens,
            address(supplier1)
        );
        testEquality(unclaimedRewardsForDaiView, unclaimedRewardsForDai);

        uint256 allUnclaimedRewardsView = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        uint256 allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        testEquality(allUnclaimedRewards, allUnclaimedRewardsView, "all unclaimed rewards 1");
        assertGt(allUnclaimedRewards, unclaimedRewardsForDai);

        supplier1.claimRewards(tokensInArray, false);
        uint256 rewardBalanceAfter = supplier1.balanceOf(comp);

        assertGt(rewardBalanceAfter, 0);

        allUnclaimedRewardsView = rewardsManager.getUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        allUnclaimedRewards = rewardsManager.accrueUserUnclaimedRewards(
            tokensInArray,
            address(supplier1)
        );
        testEquality(allUnclaimedRewardsView, allUnclaimedRewards, "all unclaimed rewards 2");
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

        rewardsManager.accrueUserUnclaimedRewards(markets, address(supplier1));

        // supplier2 tries to game the system by supplying a huge amount of tokens and withdrawing right after accruing its rewards.
        supplier2.supply(cUsdc, to6Decimals(bigAmount));
        rewardsManager.accrueUserUnclaimedRewards(markets, address(supplier2));
        supplier2.withdraw(cUsdc, to6Decimals(bigAmount));

        assertEq(
            rewardsManager.getUserUnclaimedRewards(markets, address(supplier1)),
            rewardsManager.getUserUnclaimedRewards(markets, address(supplier2))
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
        rewardsManager.accrueUserUnclaimedRewards(markets, address(supplier1));

        // User tries to claim its rewards on Morpho.
        supplier1.claimRewards(markets, false);
    }
}

contract TestRewardsInternals is TestSetup {
    using CompoundMath for uint256;

    mapping(address => IComptroller.CompMarketState) public localCompSupplyState; // The local supply state for a specific cToken.
    mapping(address => IComptroller.CompMarketState) public localCompBorrowState; // The local borrow state for a specific cToken.

    function _updateSupplyIndex(address _cTokenAddress) internal {
        IComptroller.CompMarketState storage localSupplyState = localCompSupplyState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localSupplyState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _cTokenAddress
            );

            if (supplyState.block == blockNumber) {
                localSupplyState.block = supplyState.block;
                localSupplyState.index = supplyState.index;
            } else {
                uint256 deltaBlocks = blockNumber - supplyState.block;
                uint256 supplySpeed = comptroller.compSupplySpeeds(_cTokenAddress);

                if (supplySpeed > 0) {
                    uint256 supplyTokens = ICToken(_cTokenAddress).totalSupply();
                    uint256 compAccrued = deltaBlocks * supplySpeed;
                    uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;
                    uint256 formerIndex = supplyState.index;
                    uint256 index = formerIndex + ratio;
                    localCompSupplyState[_cTokenAddress] = IComptroller.CompMarketState({
                        index: CompoundMath.safe224(index),
                        block: CompoundMath.safe32(blockNumber)
                    });
                } else localSupplyState.block = CompoundMath.safe32(blockNumber);
            }
        }
    }

    function _updateBorrowIndex(address _cTokenAddress) internal {
        IComptroller.CompMarketState storage localBorrowState = localCompBorrowState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localBorrowState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _cTokenAddress
            );

            if (borrowState.block == blockNumber) {
                localBorrowState.block = borrowState.block;
                localBorrowState.index = borrowState.index;
            } else {
                uint256 deltaBlocks = blockNumber - borrowState.block;
                uint256 borrowSpeed = comptroller.compBorrowSpeeds(_cTokenAddress);

                if (borrowSpeed > 0) {
                    uint256 borrowAmount = ICToken(_cTokenAddress).totalBorrows().div(
                        ICToken(_cTokenAddress).borrowIndex()
                    );
                    uint256 compAccrued = deltaBlocks * borrowSpeed;
                    uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;
                    uint256 formerIndex = borrowState.index;
                    uint256 index = formerIndex + ratio;
                    localBorrowState.index = CompoundMath.safe224(index);
                    localBorrowState.block = CompoundMath.safe32(blockNumber);
                } else localBorrowState.block = CompoundMath.safe32(blockNumber);
            }
        }
    }

    function testShouldUpdateSupplyIndex() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);

        hevm.roll(block.timestamp + 5_000);
        supplier1.approve(dai, cDai, type(uint256).max);
        supplier1.compoundSupply(cDai, amount);
        hevm.roll(block.timestamp + 5_000);

        supplier1.supply(cDai, amount);

        IComptroller.CompMarketState memory morphoAfter = rewardsManager.getLocalCompSupplyState(
            cDai
        );
        IComptroller.CompMarketState memory compoundAfter = comptroller.compSupplyState(cDai);

        assertEq(morphoAfter.index, compoundAfter.index);
    }

    function testShouldUpdateBorrowIndex() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, type(uint256).max);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.timestamp + 5_000);
        supplier1.approve(dai, cDai, type(uint256).max);
        supplier1.compoundSupply(cDai, amount);
        supplier1.compoundBorrow(cDai, amount / 2);
        hevm.roll(block.timestamp + 5_000);

        borrower1.borrow(cDai, amount);

        IComptroller.CompMarketState memory morphoAfter = rewardsManager.getLocalCompBorrowState(
            cDai
        );
        IComptroller.CompMarketState memory compoundAfter = comptroller.compBorrowState(cDai);

        assertEq(morphoAfter.index, compoundAfter.index);
    }

    function testShouldComputeSupplyIndex() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);

        hevm.roll(block.timestamp + 5_000);
        supplier1.approve(dai, cDai, type(uint256).max);
        supplier1.compoundSupply(cDai, amount);
        hevm.roll(block.timestamp + 5_000);

        _updateSupplyIndex(cDai);

        IComptroller.CompMarketState memory morphoAfter = localCompSupplyState[cDai];
        IComptroller.CompMarketState memory compoundAfter = comptroller.compSupplyState(cDai);

        assertEq(morphoAfter.index, compoundAfter.index);
    }

    function testShouldComputeBorrowIndex() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, type(uint256).max);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.timestamp + 5_000);
        supplier1.approve(dai, cDai, type(uint256).max);
        supplier1.compoundSupply(cDai, amount);
        supplier1.compoundBorrow(cDai, amount / 2);
        hevm.roll(block.timestamp + 5_000);

        _updateBorrowIndex(cDai);

        IComptroller.CompMarketState memory morphoAfter = localCompBorrowState[cDai];
        IComptroller.CompMarketState memory compoundAfter = comptroller.compBorrowState(cDai);

        assertEq(morphoAfter.index, compoundAfter.index);
    }
}
