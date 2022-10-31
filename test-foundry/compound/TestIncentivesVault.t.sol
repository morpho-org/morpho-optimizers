// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestIncentivesVault is TestSetup {
    using SafeTransferLib for ERC20;

    function testShouldNotSetBonusAboveMaxBasisPoints() public {
        uint256 moreThanMaxBasisPoints = incentivesVault.MAX_BASIS_POINTS() + 1;
        hevm.expectRevert(abi.encodeWithSelector(IncentivesVault.ExceedsMaxBasisPoints.selector));
        incentivesVault.setBonus(moreThanMaxBasisPoints);
    }

    function testOnlyOwnerShouldSetBonus() public {
        uint256 bonusToSet = 1;

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.setBonus(bonusToSet);

        incentivesVault.setBonus(bonusToSet);
        assertEq(incentivesVault.bonus(), bonusToSet);
    }

    function testOnlyOwnerShouldSetIncentivesTreasuryVault() public {
        address incentivesTreasuryVault = address(1);

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.setIncentivesTreasuryVault(incentivesTreasuryVault);

        incentivesVault.setIncentivesTreasuryVault(incentivesTreasuryVault);
        assertEq(incentivesVault.incentivesTreasuryVault(), incentivesTreasuryVault);
    }

    function testOnlyOwnerShouldSetOracle() public {
        IOracle oracle = IOracle(address(1));

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.setOracle(oracle);

        incentivesVault.setOracle(oracle);
        assertEq(address(incentivesVault.oracle()), address(oracle));
    }

    function testOnlyOwnerShouldSetPauseStatus() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.setPauseStatus(true);

        incentivesVault.setPauseStatus(true);
        assertTrue(incentivesVault.isPaused());

        incentivesVault.setPauseStatus(false);
        assertFalse(incentivesVault.isPaused());
    }

    function testOnlyOwnerShouldTransferTokensToDao() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.transferTokensToDao(address(morphoToken), 1);

        incentivesVault.transferTokensToDao(address(morphoToken), 1);
        assertEq(ERC20(morphoToken).balanceOf(address(treasuryVault)), 1);
    }

    function testFailWhenContractNotActive() public {
        incentivesVault.setPauseStatus(true);

        hevm.prank(address(morpho));
        incentivesVault.tradeCompForMorphoTokens(address(1), 0);
    }

    function testOnlyMorphoShouldTriggerCompConvertFunction() public {
        incentivesVault.setIncentivesTreasuryVault(address(1));
        uint256 amount = 100;
        deal(comp, address(morpho), amount);

        hevm.prank(address(morpho));
        ERC20(comp).safeApprove(address(incentivesVault), amount);

        hevm.expectRevert(abi.encodeWithSignature("OnlyMorpho()"));
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);

        hevm.prank(address(morpho));
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
    }

    function testShouldGiveTheRightAmountOfRewards() public {
        incentivesVault.setIncentivesTreasuryVault(address(1));
        uint256 toApprove = 1_000 ether;
        deal(comp, address(morpho), toApprove);

        hevm.prank(address(morpho));
        ERC20(comp).safeApprove(address(incentivesVault), toApprove);
        uint256 amount = 100;

        // O% bonus.
        uint256 balanceBefore = ERC20(morphoToken).balanceOf(address(2));
        hevm.prank(address(morpho));
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
        uint256 balanceAfter = ERC20(morphoToken).balanceOf(address(2));
        assertEq(balanceAfter - balanceBefore, 100);

        // 10% bonus.
        incentivesVault.setBonus(1_000);
        balanceBefore = ERC20(morphoToken).balanceOf(address(2));
        hevm.prank(address(morpho));
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
        balanceAfter = ERC20(morphoToken).balanceOf(address(2));
        assertEq(balanceAfter - balanceBefore, 110);
    }
}
