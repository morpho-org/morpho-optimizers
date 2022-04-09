// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestFees is TestSetup {
    using CompoundMath for uint256;

    function testShouldRevertWhenClaimingZeroAmount() public {
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        positionsManager.claimToTreasury(cDai);
    }

    function testShouldNotBePossibleToSetFeesHigherThan100Percent() public {
        marketsManager.setReserveFactor(cUsdc, 5_001);
        testEquality(marketsManager.reserveFactor(cUsdc), 5000);
    }

    function testOnlyOwnerCanSetTreasuryVault() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setTreasuryVault(address(borrower1));
    }

    function testOwnerShouldBeAbleToClaimFees() public {
        marketsManager.setReserveFactor(cDai, 1000); // 10%

        // Increase blocks so that rates update.
        hevm.roll(block.number + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 ether);
        supplier1.borrow(cDai, 50 ether);

        hevm.roll(block.number + 100);

        supplier1.repay(cDai, type(uint256).max);
        positionsManager.claimToTreasury(cDai);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());

        assertLt(balanceBefore, balanceAfter);
    }

    // TODO
    function testShouldRevertWhenClaimingToZeroAddress() public {}

    function testShouldCollectTheRightAmountOfFees() public {
        uint256 reserveFactor = 1_000;
        marketsManager.setReserveFactor(cDai, reserveFactor); // 10%

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 ether);
        supplier1.borrow(cDai, 50 ether);

        ICToken cToken = ICToken(cDai);

        (uint256 supplyP2PBPY, uint256 borrowP2PBPY) = interestRates.computeRates(
            cToken.supplyRatePerBlock(),
            cToken.borrowRatePerBlock(),
            reserveFactor
        );

        uint256 newSupplyExRate = WAD.mul(_computeCompoundedInterest(supplyP2PBPY, 100));
        uint256 newBorrowExRate = WAD.mul(_computeCompoundedInterest(borrowP2PBPY, 100));

        uint256 expectedFees = (50 * WAD).mul(newBorrowExRate) - (50 * WAD).mul(newSupplyExRate);

        hevm.roll(block.number + 100);

        supplier1.repay(cDai, type(uint256).max);
        positionsManager.claimToTreasury(cDai);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        uint256 gainedByDAO = balanceAfter - balanceBefore;

        testEquality(gainedByDAO, expectedFees, "Fees collected");
    }

    function testShouldNotClaimFeesIfFactorIsZero() public {
        marketsManager.setReserveFactor(cDai, 0);

        // Increase blocks so that rates update.
        hevm.roll(block.number + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 * WAD);
        supplier1.borrow(cDai, 50 * WAD);

        hevm.roll(block.number + 100);

        supplier1.repay(cDai, type(uint256).max);
        hevm.expectRevert(PositionsManagerForCompoundEventsErrors.AmountIsZero.selector);
        positionsManager.claimToTreasury(cDai);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());

        testEquality(balanceBefore, balanceAfter);
    }
}
