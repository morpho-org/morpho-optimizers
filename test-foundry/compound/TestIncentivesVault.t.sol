// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/compound/interfaces/IOracle.sol";
import "@contracts/compound/IncentivesVault.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "../common/helpers/MorphoToken.sol";
import "./helpers/DumbOracle.sol";
import "@forge-std/Test.sol";
import "@config/Config.sol";

contract TestIncentivesVault is Test, Config {
    using SafeTransferLib for ERC20;

    Vm public hevm = Vm(HEVM_ADDRESS);
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public morphoDao = address(1);
    address public morpho = address(3);
    IncentivesVault public incentivesVault;
    MorphoToken public morphoToken;
    DumbOracle public dumbOracle;

    function setUp() public {
        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();

        incentivesVault = new IncentivesVault(
            IComptroller(comptrollerAddress),
            IMorpho(address(morpho)),
            morphoToken,
            morphoDao,
            dumbOracle
        );
        ERC20(morphoToken).transfer(
            address(incentivesVault),
            ERC20(morphoToken).balanceOf(address(this))
        );

        hevm.label(address(morphoToken), "MORPHO");
        hevm.label(address(dumbOracle), "DumbOracle");
        hevm.label(address(incentivesVault), "IncentivesVault");
        hevm.label(COMP, "COMP");
        hevm.label(morpho, "morpho");
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
        assertEq(ERC20(morphoToken).balanceOf(morphoDao), 1);
    }

    function testFailWhenContractNotActive() public {
        incentivesVault.setPauseStatus(true);

        hevm.prank(morpho);
        incentivesVault.tradeCompForMorphoTokens(address(1), 0);
    }

    function testOnlyMorphoShouldTriggerCompConvertFunction() public {
        incentivesVault.setMorphoDao(address(1));
        uint256 amount = 100;
        deal(COMP, address(morpho), amount);

        hevm.prank(morpho);
        ERC20(COMP).safeApprove(address(incentivesVault), amount);

        hevm.expectRevert(abi.encodeWithSignature("OnlyMorpho()"));
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);

        hevm.prank(morpho);
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
    }

    function testShouldGiveTheRightAmountOfRewards() public {
        incentivesVault.setMorphoDao(address(1));
        uint256 toApprove = 1_000 ether;
        deal(COMP, address(morpho), toApprove);

        hevm.prank(morpho);
        ERC20(COMP).safeApprove(address(incentivesVault), toApprove);
        uint256 amount = 100;

        // O% bonus.
        uint256 balanceBefore = ERC20(morphoToken).balanceOf(address(2));
        hevm.prank(morpho);
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
        uint256 balanceAfter = ERC20(morphoToken).balanceOf(address(2));
        assertEq(balanceAfter - balanceBefore, 100);

        // 10% bonus.
        incentivesVault.setBonus(1_000);
        balanceBefore = ERC20(morphoToken).balanceOf(address(2));
        hevm.prank(morpho);
        incentivesVault.tradeCompForMorphoTokens(address(2), amount);
        balanceAfter = ERC20(morphoToken).balanceOf(address(2));
        assertEq(balanceAfter - balanceBefore, 110);
    }
}
