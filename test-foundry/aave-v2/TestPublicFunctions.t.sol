// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestPublicFunctions is TestSetup {
    function testUserShouldNotUpdateP2PIndexesOfMarketNotCreatedYet() public {
        hevm.prank(address(2));
        hevm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.updateIndexes(aWeth);
    }
}
