// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestMorphoUtils is TestSetup {
    function testUserShouldNotUpdateP2PIndexesOfMarketNotCreated() public {
        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.updateP2PIndexes(cAave);
    }
}
