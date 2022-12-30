// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestPublicFunctions is TestSetup {
    function testUserShouldNotUpdateP2PIndexesOfMarketNotCreatedYet() public {
        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.updateIndexes(aWeth);
    }
}
