// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestFees is TestSetup {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    address[] aDaiArray = [aDai];

    function testShouldNotBePossibleToSetFeesHigherThan100Percent() public {
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.setReserveFactor(aUsdc, 10_001);
    }

    function testShouldNotBePossibleToSetP2PIndexCursorHigherThan100Percent() public {
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.setP2PIndexCursor(aUsdc, 10_001);
    }

    function testOnlyOwnerCanSetTreasuryVault() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setTreasuryVault(address(borrower1));
    }

    function testOwnerShouldBeAbleToClaimFees() public {
        uint256 balanceBefore = IERC20(dai).balanceOf(morpho.treasuryVault());
        _createFeeOnMorpho(1_000);
        morpho.claimToTreasury(aDaiArray);
        uint256 balanceAfter = IERC20(dai).balanceOf(morpho.treasuryVault());

        assertLt(balanceBefore, balanceAfter);
    }

    function testShouldRevertWhenClaimingToZeroAddress() public {
        // Set treasury vault to 0x.
        morpho.setTreasuryVault(address(0));

        _createFeeOnMorpho(1_000);

        hevm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        morpho.claimToTreasury(aDaiArray);
    }

    function testShouldCollectTheRightAmountOfFees() public {
        uint16 reserveFactor = 1_000;
        uint256 toBorrow = 50 ether;
        morpho.setReserveFactor(aDai, reserveFactor); // 10%

        uint256 balanceBefore = IERC20(dai).balanceOf(morpho.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 ether);
        supplier1.borrow(aDai, toBorrow);

        uint256 oldSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 oldBorrowIndex = morpho.p2pBorrowIndex(aDai);

        hevm.warp(block.timestamp + 365 days);
        (uint256 newSupplyIndex, uint256 newBorrowIndex) = lens.getUpdatedP2PIndexes(aDai);

        uint256 expectedFees = toBorrow
        .rayMul(newBorrowIndex.rayDiv(oldBorrowIndex) - newSupplyIndex.rayDiv(oldSupplyIndex))
        .percentMul(morpho.MAX_CLAIMABLE_RESERVE());

        supplier1.repay(aDai, type(uint256).max);
        morpho.claimToTreasury(aDaiArray);
        uint256 balanceAfter = IERC20(dai).balanceOf(morpho.treasuryVault());
        uint256 gainedByDAO = balanceAfter - balanceBefore;

        assertApproxEqAbs(gainedByDAO, expectedFees, (expectedFees * 1) / 100000, "Fees collected");
    }

    function testShouldNotClaimFeesIfFactorIsZero() public {
        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));

        _createFeeOnMorpho(0);

        morpho.claimToTreasury(aDaiArray);

        uint256 balanceAfter = ERC20(dai).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore);
    }

    function testShouldNotClaimFeesIfMarketIsPaused() public {
        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        _createFeeOnMorpho(1_000);

        // Pause market.
        morpho.setPauseStatus(aDai, true);

        morpho.claimToTreasury(aDaiArray);

        uint256 balanceAfter = ERC20(dai).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore);
    }

    function testShouldNotClaimFeesIfMarketIsPartiallyPaused() public {
        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));
        _createFeeOnMorpho(1_000);

        // Partially pause market.
        morpho.setPartialPauseStatus(aDai, true);

        morpho.claimToTreasury(aDaiArray);

        uint256 balanceAfter = ERC20(dai).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore);
    }

    function testShouldPayFee() public {
        uint16 reserveFactor = 1_000;
        uint256 bigAmount = 100_000 ether;
        uint256 smallAmount = 0.00001 ether;
        morpho.setReserveFactor(aDai, reserveFactor); // 10%

        // Increase time so that rates update.
        hevm.warp(block.timestamp + 1);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, smallAmount);
        supplier1.borrow(aDai, smallAmount / 2);

        supplier2.approve(dai, type(uint256).max);
        supplier2.supply(aDai, bigAmount);
        supplier2.borrow(aDai, bigAmount / 2);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);
    }

    function testShouldReduceTheFeeToRepay() public {
        uint16 reserveFactor = 1_000;
        uint256 bigAmount = 100_000 ether;
        uint256 smallAmount = 0.00001 ether;
        morpho.setReserveFactor(aDai, reserveFactor); // 10%

        // Increase time so that rates update.
        hevm.warp(block.timestamp + 1);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, smallAmount);
        supplier1.borrow(aDai, smallAmount / 2);

        supplier2.approve(dai, type(uint256).max);
        supplier2.supply(aDai, bigAmount);
        supplier2.borrow(aDai, bigAmount / 2);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);
        supplier2.repay(aDai, type(uint256).max);
    }

    /// HELPERS ///

    function _createFeeOnMorpho(uint16 _factor) internal {
        morpho.setReserveFactor(aDai, _factor);

        // Increase time so that rates update.
        hevm.warp(block.timestamp + 1);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 * WAD);
        supplier1.borrow(aDai, 50 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);
    }
}
