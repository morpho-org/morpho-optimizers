// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestFees is TestSetup {
    using CompoundMath for uint256;

    function testShouldRevertWhenClaimingZeroAmount() public {
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        positionsManager.claimToTreasury(cDai, 1 ether);
    }

    function testShouldNotBePossibleToSetFeesHigherThan100Percent() public {
        positionsManager.setReserveFactor(cUsdc, 10_001);
        (uint16 reserveFactor, ) = positionsManager.marketParameters(cUsdc);
        assertEq(reserveFactor, 10_000);
    }

    function testOnlyOwnerCanSetTreasuryVault() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setTreasuryVault(address(borrower1));
    }

    function testOwnerShouldBeAbleToClaimFees() public {
        positionsManager.setReserveFactor(cDai, 1000); // 10%

        // Increase blocks so that rates update.
        hevm.roll(block.number + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 ether);
        supplier1.borrow(cDai, 50 ether);

        move1000BlocksForward(cDai);

        supplier1.repay(cDai, type(uint256).max);
        positionsManager.claimToTreasury(cDai, 1 ether);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());

        assertLt(balanceBefore, balanceAfter);
    }

    function testShouldRevertWhenClaimingToZeroAddress() public {
        // Set treasury vault to 0x.
        positionsManager.setTreasuryVault(address(0));

        positionsManager.setReserveFactor(cDai, 1_000); // 10%

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 * WAD);
        supplier1.borrow(cDai, 50 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(cDai, type(uint256).max);

        hevm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        positionsManager.claimToTreasury(cDai, 1 ether);
    }

    function testShouldCollectTheRightAmountOfFees() public {
        uint256 reserveFactor = 1_000;
        positionsManager.setReserveFactor(cDai, reserveFactor); // 10%

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 ether);
        supplier1.borrow(cDai, 50 ether);

        uint256 oldSupplyExRate = positionsManager.p2pSupplyIndex(cDai);
        uint256 oldBorrowExRate = positionsManager.p2pBorrowIndex(cDai);

        (uint256 supplyP2PBPY, uint256 borrowP2PBPY) = getApproxBPYs(cDai);

        uint256 newSupplyExRate = oldSupplyExRate.mul(
            _computeCompoundedInterest(supplyP2PBPY, 1000)
        );
        uint256 newBorrowExRate = oldBorrowExRate.mul(
            _computeCompoundedInterest(borrowP2PBPY, 1000)
        );

        uint256 expectedFees = (50 * WAD).mul(
            newBorrowExRate.div(oldBorrowExRate) - newSupplyExRate.div(oldSupplyExRate)
        );

        move1000BlocksForward(cDai);

        supplier1.repay(cDai, type(uint256).max);
        positionsManager.claimToTreasury(cDai, type(uint256).max);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        uint256 gainedByDAO = balanceAfter - balanceBefore;

        assertApproxEq(
            gainedByDAO,
            (expectedFees * 9_000) / MAX_BASIS_POINTS,
            (expectedFees * 1) / 100000,
            "Fees collected"
        );
    }

    function testShouldNotClaimFeesIfFactorIsZero() public {
        positionsManager.setReserveFactor(cDai, 0);

        // Increase blocks so that rates update.
        hevm.roll(block.number + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 * WAD);
        supplier1.borrow(cDai, 50 * WAD);

        hevm.roll(block.number + 100);

        supplier1.repay(cDai, type(uint256).max);
        hevm.expectRevert(PositionsManagerEventsErrors.AmountIsZero.selector);
        positionsManager.claimToTreasury(cDai, 1 ether);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());

        assertEq(balanceBefore, balanceAfter);
    }
}
