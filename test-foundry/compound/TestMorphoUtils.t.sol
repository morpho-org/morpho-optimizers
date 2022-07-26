// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@setup/TestSetup.sol";

contract TestMorphoUtils is TestSetup {
    function testUserShouldNotUpdateP2PIndexesOfMarketNotCreated() public {
        hevm.prank(address(2));
        hevm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.updateP2PIndexes(cAave);
    }
}
