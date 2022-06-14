// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestTokenizedVault is TestSetup {
    using CompoundMath for uint256;

    function testShouldDepositAmount() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, amount / 2);
        supplier1.supply(cDai, amount / 2);

        supplier1.approve(dai, address(mcDai), amount / 2);
        supplier1.depositVault(mcDai, amount / 2);

        (uint256 tokenizedVaultOnPool, uint256 tokenizedVaultInP2P) = morpho.supplyBalanceInOf(
            cDai,
            address(mcDai)
        );
        (uint256 supplier1OnPool, uint256 supplier1InP2P) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        assertGt(mcDai.balanceOf(address(supplier1)), 0, "mcDAI balance is zero");
        assertEq(tokenizedVaultOnPool, supplier1OnPool, "onPool amount different");
        assertEq(tokenizedVaultInP2P, supplier1InP2P, "inP2P amount different");
    }

    function testShouldWithdrawAllAmount() public {
        uint256 amount = 10000 ether;

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(poolSupplyIndex);

        supplier1.approve(dai, address(mcDai), amount);
        supplier1.depositVault(mcDai, amount);
        supplier1.withdrawVault(mcDai, expectedOnPool.mul(poolSupplyIndex));

        (uint256 tokenizedVaultOnPool, uint256 tokenizedVaultInP2P) = morpho.supplyBalanceInOf(
            cDai,
            address(mcDai)
        );

        assertApproxEq(mcDai.balanceOf(address(supplier1)), 0, 10, "mcDAI balance not zero");
        assertEq(tokenizedVaultOnPool, 0, "onPool amount not zero");
        assertEq(tokenizedVaultInP2P, 0, "inP2P amount not zero");
    }

    function testShouldWithdrawAllShares() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        uint256 shares = supplier1.depositVault(mcDai, amount);
        supplier1.redeemVault(mcDai, shares); // cannot withdraw amount because of Compound rounding errors

        (uint256 tokenizedVaultOnPool, uint256 tokenizedVaultInP2P) = morpho.supplyBalanceInOf(
            cDai,
            address(mcDai)
        );

        assertEq(mcDai.balanceOf(address(supplier1)), 0, "mcDAI balance not zero");
        assertEq(tokenizedVaultOnPool, 0, "onPool amount not zero");
        assertEq(tokenizedVaultInP2P, 0, "inP2P amount not zero");
    }

    function testShouldNotWithdrawWhenNotDeposited() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        uint256 shares = supplier1.depositVault(mcDai, amount);

        hevm.expectRevert("ERC20: burn amount exceeds balance");
        supplier2.redeemVault(mcDai, shares);
    }

    function testShouldNotWithdrawOnBehalfIfNotAllowed() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        uint256 shares = supplier1.depositVault(mcDai, amount);

        hevm.expectRevert("ERC20: insufficient allowance");
        supplier1.redeemVault(mcDai, shares, address(supplier2));
    }

    function testShouldWithdrawOnBehalfIfAllowed() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        uint256 shares = supplier1.depositVault(mcDai, amount);

        supplier1.approve(address(mcDai), address(supplier2), shares);
        supplier2.redeemVault(mcDai, shares, address(supplier1));
    }

    function testShouldNotDepositZeroAmount() public {
        hevm.expectRevert(abi.encodeWithSignature("ShareIsZero()"));
        supplier1.depositVault(mcDai, 0);
    }

    function testShouldNotMintZeroShare() public {
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        supplier1.mintVault(mcDai, 0);
    }

    function testShouldNotWithdrawGreaterAmount() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        supplier1.depositVault(mcDai, amount);

        hevm.expectRevert("ERC20: burn amount exceeds balance");
        supplier1.withdrawVault(mcDai, amount * 2);
    }

    function testShouldNotRedeemMoreShares() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        uint256 shares = supplier1.depositVault(mcDai, amount);

        hevm.expectRevert("ERC20: burn amount exceeds balance");
        supplier1.redeemVault(mcDai, shares + 1);
    }

    function testShouldClaimAndFoldRewards() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        supplier1.depositVault(mcDai, amount);

        (, uint256 balanceInP2PBefore) = morpho.supplyBalanceInOf(cDai, address(mcDai));

        hevm.roll(block.number + 1_000);

        (uint256 rewardsAmount, ) = mcDai.claimRewards(3000);
        (, uint256 balanceInP2PAfter) = morpho.supplyBalanceInOf(cDai, address(mcDai));
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);

        assertGt(rewardsAmount, 0);
        assertApproxEq(
            balanceInP2PAfter,
            balanceInP2PBefore + rewardsAmount.div(p2pSupplyIndex),
            1e9
        );
        assertEq(ERC20(comptroller.getCompAddress()).balanceOf(address(mcDai)), 0);
    }

    function testShouldClaimAndRedeemRewards() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(mcDai), amount);
        uint256 shares = supplier1.depositVault(mcDai, amount);

        hevm.roll(block.number + 1_000);

        morpho.updateP2PIndexes(cDai);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier1));

        (uint256 rewardsAmount, uint256 rewardsFee) = mcDai.claimRewards(3000);
        supplier1.redeemVault(mcDai, shares);
        uint256 balanceAfter = ERC20(dai).balanceOf(address(supplier1));

        assertEq(ERC20(dai).balanceOf(address(mcDai)), 0);
        assertGt(balanceAfter, balanceBefore + rewardsAmount);

        assertEq(ERC20(dai).balanceOf(address(this)), rewardsFee);
        assertEq(rewardsFee, ((rewardsAmount + rewardsFee) * 10) / 10_000);
    }
}
