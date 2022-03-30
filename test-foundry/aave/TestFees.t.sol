// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestFees is TestSetup {
    using Math for uint256;

    function testShouldRevertWhenClaimingZeroAmount() public {
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        positionsManager.claimToTreasury(aDai);
    }

    function testShouldNotBePossibleToSetFeesHigherThan50Percent() public {
        marketsManager.setReserveFactor(aUsdc, 5_001);
        testEquality(marketsManager.reserveFactor(aUsdc), 5_000);
    }

    function testOnlyOwnerCanSetTreasuryVault() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setTreasuryVault(address(borrower1));
    }

    function testOwnerShouldBeAbleToClaimFees() public {
        marketsManager.setReserveFactor(aDai, 1_000); // 10%

        // Increase time so that rates update.
        hevm.warp(block.timestamp + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 * WAD);
        supplier1.borrow(aDai, 50 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);
        positionsManager.claimToTreasury(aDai);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());

        assertLt(balanceBefore, balanceAfter);
    }

    function testShouldRevertWhenClaimingToZeroAddress() public {
        // Set treasury vault to 0x.
        positionsManager.setTreasuryVault(address(0));

        marketsManager.setReserveFactor(aDai, 1_000); // 10%

        // Increase time so that rates update.
        hevm.warp(block.timestamp + 1);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 * WAD);
        supplier1.borrow(aDai, 50 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);

        hevm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        positionsManager.claimToTreasury(aDai);
    }

    function testShouldCollectTheRightAmountOfFees() public {
        marketsManager.setReserveFactor(aDai, 1000); // 10%

        // Increase time so that rates update.
        hevm.warp(block.timestamp + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 * WAD);
        supplier1.borrow(aDai, 50 * WAD);

        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(aDai).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 meanSPY = Math.average(
            reserveData.currentLiquidityRate,
            reserveData.currentVariableBorrowRate
        ) / (365 days); // In ray.

        uint256 supplyP2PSPY = (meanSPY * 9_000) / MAX_BASIS_POINTS;
        uint256 borrowP2PSPY = (meanSPY * 11_000) / MAX_BASIS_POINTS;

        uint256 newSupplyExRate = RAY.rayMul(computeCompoundedInterest(supplyP2PSPY, 365 days));
        uint256 newBorrowExRate = RAY.rayMul(computeCompoundedInterest(borrowP2PSPY, 365 days));

        uint256 expectedFees = (50 * WAD).rayMul(newBorrowExRate) -
            (50 * WAD).rayMul(newSupplyExRate);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);
        positionsManager.claimToTreasury(aDai);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        uint256 gainedByDAO = balanceAfter - balanceBefore;

        assertApproxEq(gainedByDAO, expectedFees, 2);
    }

    function testShouldNotClaimFeesIfFactorIsZero() public {
        marketsManager.setReserveFactor(aDai, 0);

        // Increase time so that rates update.
        hevm.warp(block.timestamp + 1);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 * WAD);
        supplier1.borrow(aDai, 50 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);

        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        positionsManager.claimToTreasury(aDai);
    }
}
