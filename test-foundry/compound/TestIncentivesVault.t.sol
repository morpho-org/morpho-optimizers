// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestIncentivesVault is TestSetup {
    function testShouldGiveTheRightAmountOfRewards() public {}

    function testOnlyOwnerShouldSetBonus() public {}

    function testOnlyOwnerShouldSetMorphoDao() public {}

    function testOnlyOwnerShouldSetOracle() public {}

    function testOnlyOwnerShouldToggleActivation() public {}

    function testOnlyOwnerShouldTransferMorphoTokensToDao() public {}

    function testOnlyPositonsShouldTriggerCompConvertFunction() public {}

    function testFailWhenContractNotActive() public {}
}
