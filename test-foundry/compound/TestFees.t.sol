// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestFees is TestSetup {
    using CompoundMath for uint256;

    function testShouldRevertWhenClaimingZeroAmount() public {
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        morpho.claimToTreasury(cDai, 1 ether);
    }

    function testShouldNotBePossibleToSetFeesHigherThan100Percent() public {
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.setReserveFactor(cUsdc, 10_001);
    }

    function testShouldNotBePossibleToSetP2PIndexCursorHigherThan100Percent() public {
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.setP2PIndexCursor(cUsdc, 10_001);
    }

    function testOnlyOwnerCanSetTreasuryVault() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setTreasuryVault(address(borrower1));
    }

    function testOwnerShouldBeAbleToClaimFees() public {
        morpho.setReserveFactor(cDai, 1000); // 10%

        // Increase blocks so that rates update.
        hevm.roll(block.number + 1);

        uint256 balanceBefore = ERC20(dai).balanceOf(morpho.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 ether);
        supplier1.borrow(cDai, 50 ether);

        move1000BlocksForward(cDai);

        supplier1.repay(cDai, type(uint256).max);
        morpho.claimToTreasury(cDai, 1 ether);
        uint256 balanceAfter = ERC20(dai).balanceOf(morpho.treasuryVault());

        assertLt(balanceBefore, balanceAfter);
    }

    function testShouldRevertWhenClaimingToZeroAddress() public {
        // Set treasury vault to 0x.
        morpho.setTreasuryVault(address(0));

        morpho.setReserveFactor(cDai, 1_000); // 10%

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 * WAD);
        supplier1.borrow(cDai, 50 * WAD);

        hevm.roll(block.number + 1_000);

        supplier1.repay(cDai, type(uint256).max);

        hevm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        morpho.claimToTreasury(cDai, 1 ether);
    }

    function testShouldCollectTheRightAmountOfFees() public {
        uint16 reserveFactor = 1_000;
        morpho.setReserveFactor(cDai, reserveFactor); // 10%

        uint256 balanceBefore = ERC20(dai).balanceOf(morpho.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 ether);
        supplier1.borrow(cDai, 50 ether);

        uint256 oldSupplyExRate = morpho.p2pSupplyIndex(cDai);
        uint256 oldBorrowExRate = morpho.p2pBorrowIndex(cDai);

        (uint256 supplyP2PBPY, uint256 borrowP2PBPY) = getApproxP2PRates(cDai);

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
        morpho.claimToTreasury(cDai, type(uint256).max);
        uint256 balanceAfter = ERC20(dai).balanceOf(morpho.treasuryVault());
        uint256 gainedByDAO = balanceAfter - balanceBefore;

        assertApproxEq(
            gainedByDAO,
            (expectedFees * 9_000) / MAX_BASIS_POINTS,
            (expectedFees * 1) / 100000,
            "Fees collected"
        );
    }

    function testShouldNotClaimFeesIfFactorIsZero() public {
        morpho.setReserveFactor(cDai, 0);

        // Increase blocks so that rates update.
        hevm.roll(block.number + 1);

        uint256 balanceBefore = ERC20(dai).balanceOf(morpho.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 * WAD);
        supplier1.borrow(cDai, 50 * WAD);

        hevm.roll(block.number + 100);

        supplier1.repay(cDai, type(uint256).max);
        hevm.expectRevert(MorphoGovernance.AmountIsZero.selector);
        morpho.claimToTreasury(cDai, 1 ether);
        uint256 balanceAfter = ERC20(dai).balanceOf(morpho.treasuryVault());

        testEquality(balanceBefore, balanceAfter);
    }

    function testShouldPayFee() public {
        uint16 reserveFactor = 1_000;
        uint256 bigAmount = 100_000 ether;
        uint256 smallAmount = 0.00001 ether;
        morpho.setReserveFactor(cDai, reserveFactor); // 10%

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, smallAmount);
        supplier1.borrow(cDai, smallAmount / 2);

        supplier2.approve(dai, type(uint256).max);
        supplier2.supply(cDai, bigAmount);
        supplier2.borrow(cDai, bigAmount / 2);

        move1000BlocksForward(cDai);

        supplier1.repay(cDai, type(uint256).max);
    }

    function testShouldReduceTheFeeToRepay() public {
        uint16 reserveFactor = 1_000;
        uint256 bigAmount = 100_000 ether;
        uint256 smallAmount = 0.00001 ether;
        morpho.setReserveFactor(cDai, reserveFactor); // 10%

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, smallAmount);
        supplier1.borrow(cDai, smallAmount / 2);

        supplier2.approve(dai, type(uint256).max);
        supplier2.supply(cDai, bigAmount);
        supplier2.borrow(cDai, bigAmount / 2);

        move1000BlocksForward(cDai);

        supplier1.repay(cDai, type(uint256).max);
        supplier2.repay(cDai, type(uint256).max);
    }
}
