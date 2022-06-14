// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestSupplyVault is TestSetup {
    using CompoundMath for uint256;

    function testShouldDepositAmount() public {
        uint256 amount = 10000 ether;

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedInP2P = amount.div(poolSupplyIndex);

        supplier1.approve(dai, address(daiSupplyVault), amount);
        supplier1.depositVault(daiSupplyVault, amount);

        (uint256 tokenizedVaultOnPool, uint256 tokenizedVaultInP2P) = morpho.supplyBalanceInOf(
            cDai,
            address(daiSupplyVault)
        );

        assertGt(daiSupplyVault.balanceOf(address(supplier1)), 0, "mcDAI balance is zero");
        assertEq(tokenizedVaultOnPool, 0, "onPool amount not zero");
        assertEq(tokenizedVaultInP2P, expectedInP2P, "unexpected inP2P amount");
    }

    function testShouldWithdrawAllAmount() public {
        uint256 amount = 10000 ether;

        uint256 poolSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(poolSupplyIndex);

        supplier1.approve(dai, address(daiSupplyVault), amount);
        supplier1.depositVault(daiSupplyVault, amount);
        supplier1.withdrawVault(daiSupplyVault, expectedOnPool.mul(poolSupplyIndex));

        (uint256 tokenizedVaultOnPool, uint256 tokenizedVaultInP2P) = morpho.supplyBalanceInOf(
            cDai,
            address(daiSupplyVault)
        );

        assertApproxEq(
            daiSupplyVault.balanceOf(address(supplier1)),
            0,
            10,
            "mcDAI balance not zero"
        );
        assertEq(tokenizedVaultOnPool, 0, "onPool amount not zero");
        assertEq(tokenizedVaultInP2P, 0, "inP2P amount not zero");
    }

    function testShouldWithdrawAllUsdcAmount() public {
        uint256 amount = 1e9;

        uint256 poolSupplyIndex = ICToken(cUsdc).exchangeRateCurrent();
        uint256 expectedOnPool = amount.div(poolSupplyIndex);

        supplier1.approve(usdc, address(usdcSupplyVault), amount);
        supplier1.depositVault(usdcSupplyVault, amount);
        supplier1.withdrawVault(usdcSupplyVault, expectedOnPool.mul(poolSupplyIndex));

        (uint256 tokenizedVaultOnPool, uint256 tokenizedVaultInP2P) = morpho.supplyBalanceInOf(
            cUsdc,
            address(usdcSupplyVault)
        );

        assertApproxEq(
            usdcSupplyVault.balanceOf(address(supplier1)),
            0,
            10,
            "mcUSDT balance not zero"
        );
        assertEq(tokenizedVaultOnPool, 0, "onPool amount not zero");
        assertEq(tokenizedVaultInP2P, 0, "inP2P amount not zero");
    }

    function testShouldWithdrawAllShares() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        uint256 shares = supplier1.depositVault(daiSupplyVault, amount);
        supplier1.redeemVault(daiSupplyVault, shares); // cannot withdraw amount because of Compound rounding errors

        (uint256 tokenizedVaultOnPool, uint256 tokenizedVaultInP2P) = morpho.supplyBalanceInOf(
            cDai,
            address(daiSupplyVault)
        );

        assertEq(daiSupplyVault.balanceOf(address(supplier1)), 0, "mcDAI balance not zero");
        assertEq(tokenizedVaultOnPool, 0, "onPool amount not zero");
        assertEq(tokenizedVaultInP2P, 0, "inP2P amount not zero");
    }

    function testShouldNotWithdrawWhenNotDeposited() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        uint256 shares = supplier1.depositVault(daiSupplyVault, amount);

        hevm.expectRevert("ERC20: burn amount exceeds balance");
        supplier2.redeemVault(daiSupplyVault, shares);
    }

    function testShouldNotWithdrawOnBehalfIfNotAllowed() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        uint256 shares = supplier1.depositVault(daiSupplyVault, amount);

        hevm.expectRevert("ERC20: insufficient allowance");
        supplier1.redeemVault(daiSupplyVault, shares, address(supplier2));
    }

    function testShouldWithdrawOnBehalfIfAllowed() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        uint256 shares = supplier1.depositVault(daiSupplyVault, amount);

        supplier1.approve(address(daiSupplyVault), address(supplier2), shares);
        supplier2.redeemVault(daiSupplyVault, shares, address(supplier1));
    }

    function testShouldNotDepositZeroAmount() public {
        hevm.expectRevert(abi.encodeWithSignature("ShareIsZero()"));
        supplier1.depositVault(daiSupplyVault, 0);
    }

    function testShouldNotMintZeroShare() public {
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        supplier1.mintVault(daiSupplyVault, 0);
    }

    function testShouldNotWithdrawGreaterAmount() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        supplier1.depositVault(daiSupplyVault, amount);

        hevm.expectRevert("ERC20: burn amount exceeds balance");
        supplier1.withdrawVault(daiSupplyVault, amount * 2);
    }

    function testShouldNotRedeemMoreShares() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        uint256 shares = supplier1.depositVault(daiSupplyVault, amount);

        hevm.expectRevert("ERC20: burn amount exceeds balance");
        supplier1.redeemVault(daiSupplyVault, shares + 1);
    }

    function testShouldClaimAndFoldRewards() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        supplier1.depositVault(daiSupplyVault, amount);

        (, uint256 balanceInP2PBefore) = morpho.supplyBalanceInOf(cDai, address(daiSupplyVault));

        hevm.roll(block.number + 1_000);

        (uint256 rewardsAmount, ) = daiSupplyVault.claimRewards(3000);
        (, uint256 balanceInP2PAfter) = morpho.supplyBalanceInOf(cDai, address(daiSupplyVault));
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);

        assertGt(rewardsAmount, 0);
        assertApproxEq(
            balanceInP2PAfter,
            balanceInP2PBefore + rewardsAmount.div(p2pSupplyIndex),
            1e9
        );
        assertEq(ERC20(comptroller.getCompAddress()).balanceOf(address(daiSupplyVault)), 0);
    }

    function testShouldClaimAndRedeemRewards() public {
        uint256 amount = 10000 ether;

        supplier1.approve(dai, address(daiSupplyVault), amount);
        uint256 shares = supplier1.depositVault(daiSupplyVault, amount);

        hevm.roll(block.number + 1_000);

        morpho.updateP2PIndexes(cDai);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier1));

        (uint256 rewardsAmount, uint256 rewardsFee) = daiSupplyVault.claimRewards(3000);
        supplier1.redeemVault(daiSupplyVault, shares);
        uint256 balanceAfter = ERC20(dai).balanceOf(address(supplier1));

        assertEq(ERC20(dai).balanceOf(address(daiSupplyVault)), 0);
        assertGt(balanceAfter, balanceBefore + rewardsAmount);

        assertEq(ERC20(dai).balanceOf(address(this)), rewardsFee);
        assertEq(rewardsFee, ((rewardsAmount + rewardsFee) * 10) / 10_000);
    }
}
