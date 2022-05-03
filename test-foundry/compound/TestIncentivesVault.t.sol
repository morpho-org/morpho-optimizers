// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/comp-rewards/IncentivesVault.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "../common/helpers/MorphoToken.sol";
import "./helpers/DumbOracle.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "ds-test/test.sol";

contract TestIncentivesVault is DSTest, stdCheats {
    using SafeTransferLib for ERC20;

    Vm public hevm = Vm(HEVM_ADDRESS);
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public morphoDao = address(1);
    address public positionsManager = address(3);
    IncentivesVault public incentivesVault;
    MorphoToken public morphoToken;
    DumbOracle public dumbOracle;

    function setUp() public {
        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();
        incentivesVault = new IncentivesVault(
            positionsManager,
            address(morphoToken),
            morphoDao,
            address(dumbOracle)
        );
        ERC20(morphoToken).transfer(
            address(incentivesVault),
            ERC20(morphoToken).balanceOf(address(this))
        );

        hevm.label(address(morphoToken), "MORPHO");
        hevm.label(address(dumbOracle), "DumbOracle");
        hevm.label(address(incentivesVault), "IncentivesVault");
        hevm.label(COMP, "COMP");
        hevm.label(positionsManager, "PositionsManager");
    }

    function testOnlyOwnerShouldSetBonus() public {
        uint256 bonusToSet = 1;

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.setBonus(bonusToSet);

        incentivesVault.setBonus(bonusToSet);
        assertEq(incentivesVault.bonus(), bonusToSet);
    }

    function testOnlyOwnerShouldSetMorphoDao() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.setMorphoDao(morphoDao);

        incentivesVault.setMorphoDao(morphoDao);
        assertEq(incentivesVault.morphoDao(), morphoDao);
    }

    function testOnlyOwnerShouldSetOracle() public {
        address oracle = address(1);

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.setOracle(oracle);

        incentivesVault.setOracle(oracle);
        assertEq(incentivesVault.oracle(), oracle);
    }

    function testOnlyOwnerShouldTogglePauseStatus() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.togglePauseStatus();

        incentivesVault.togglePauseStatus();
        assertTrue(incentivesVault.isPaused());

        incentivesVault.togglePauseStatus();
        assertFalse(incentivesVault.isPaused());
    }

    function testOnlyOwnerShouldTransferMorphoTokensToDao() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        incentivesVault.transferMorphoTokensToDao(1);

        incentivesVault.transferMorphoTokensToDao(1);
        assertEq(ERC20(morphoToken).balanceOf(morphoDao), 1);
    }

    function testFailWhenContractNotActive() public {
        incentivesVault.togglePauseStatus();

        hevm.prank(positionsManager);
        incentivesVault.tradeCompForMorphoTokens(address(1), 0);
    }

    function testOnlyPositionsManagerShouldTriggerCompConvertFunction() public {
        incentivesVault.setMorphoDao(address(1));

        hevm.expectRevert(abi.encodeWithSignature("OnlyMorpho()"));
        incentivesVault.tradeCompForMorphoTokens(address(2), 0);

        hevm.prank(positionsManager);
        incentivesVault.tradeCompForMorphoTokens(address(2), 0);
    }

    function testShouldGiveTheRightAmountOfRewards() public {
        incentivesVault.setMorphoDao(address(1));
        uint256 toApprove = 1_000 ether;
        tip(COMP, address(positionsManager), toApprove);

        hevm.prank(positionsManager);
        ERC20(COMP).safeApprove(address(incentivesVault), toApprove);
        uint256 amount = 100;

        // O% bonus.
        uint256 balanceBefore = ERC20(morphoToken).balanceOf(address(2));
        hevm.prank(positionsManager);
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
        uint256 balanceAfter = ERC20(morphoToken).balanceOf(address(2));
        assertEq(balanceAfter - balanceBefore, 100);

        // 10% bonus.
        incentivesVault.setBonus(1_000);
        balanceBefore = ERC20(morphoToken).balanceOf(address(2));
        hevm.prank(positionsManager);
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
        balanceAfter = ERC20(morphoToken).balanceOf(address(2));
        assertEq(balanceAfter - balanceBefore, 110);
    }
}
