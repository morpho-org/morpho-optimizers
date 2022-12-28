// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestFees is TestSetup {
    using CompoundMath for uint256;

    address[] cDaiArray = [cDai];
    uint256[] public amountArray = [1 ether];
    uint256[] public maxAmountArray = [type(uint256).max];

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
        uint256 balanceBefore = ERC20(dai).balanceOf(morpho.treasuryVault());
        _createFeeOnMorpho(1_000);
        morpho.claimToTreasury(cDaiArray, maxAmountArray);
        uint256 balanceAfter = ERC20(dai).balanceOf(morpho.treasuryVault());

        assertLt(balanceBefore, balanceAfter);
    }

    function testShouldRevertWhenClaimingToZeroAddress() public {
        // Set treasury vault to 0x.
        morpho.setTreasuryVault(address(0));

        _createFeeOnMorpho(1_000);

        hevm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        morpho.claimToTreasury(cDaiArray, amountArray);
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
        morpho.claimToTreasury(cDaiArray, maxAmountArray);
        uint256 balanceAfter = ERC20(dai).balanceOf(morpho.treasuryVault());
        uint256 gainedByDAO = balanceAfter - balanceBefore;

        assertApproxEqAbs(gainedByDAO, expectedFees, (expectedFees * 1) / 100000, "Fees collected");
    }

    function testShouldNotClaimFeesIfFactorIsZero() public {
        uint256 balanceBefore = ERC20(dai).balanceOf(address(this));

        _createFeeOnMorpho(0);

        morpho.claimToTreasury(cDaiArray, maxAmountArray);

        uint256 balanceAfter = ERC20(dai).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore);
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

    function testShouldNotClaimCompRewards() public {
        uint256 amount = 1_000 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);
        supplier2.approve(dai, type(uint256).max);
        supplier2.supply(cDai, amount);

        move1000BlocksForward(cDai);

        // Claim rewards for supplier1 and supplier2. Only COMP rewards for supplier2 are left on the contract.
        supplier1.claimRewards(cDaiArray, false);

        // Try to claim COMP to treasury.
        uint256 balanceBefore = ERC20(comp).balanceOf(address(morpho));
        address[] memory cCompArray = new address[](1);
        cCompArray[0] = cComp;
        morpho.claimToTreasury(cCompArray, amountArray);
        uint256 balanceAfter = ERC20(comp).balanceOf(address(morpho));

        assertEq(balanceAfter, balanceBefore);
    }

    /// HELPERS ///

    function _createFeeOnMorpho(uint16 _factor) internal {
        morpho.setReserveFactor(cDai, _factor);

        // Increase blocks so that rates update.
        hevm.roll(block.number + 1);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 100 * WAD);
        supplier1.borrow(cDai, 50 * WAD);

        move1000BlocksForward(cDai);

        supplier1.repay(cDai, type(uint256).max);
    }
}
