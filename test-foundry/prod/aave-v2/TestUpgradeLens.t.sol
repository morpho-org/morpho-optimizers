// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeLens is TestSetup {
    struct Indexes {
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
    }

    function testShouldPreserveUpdatedIndexes() public {
        Indexes[] memory expectedIndexes = new Indexes[](markets.length);

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            (
                uint256 p2pSupplyIndex,
                uint256 p2pBorrowIndex,
                uint256 poolSupplyIndex,
                uint256 poolBorrowIndex
            ) = lens.getIndexes(markets[marketIndex].poolToken);

            expectedIndexes[marketIndex].p2pSupplyIndex = p2pSupplyIndex;
            expectedIndexes[marketIndex].p2pBorrowIndex = p2pBorrowIndex;
            expectedIndexes[marketIndex].poolSupplyIndex = poolSupplyIndex;
            expectedIndexes[marketIndex].poolBorrowIndex = poolBorrowIndex;
        }

        vm.startPrank(address(proxyAdmin));
        lensProxy.upgradeTo(address(new Lens(address(morpho))));
        vm.stopPrank();

        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            (
                uint256 p2pSupplyIndex,
                uint256 p2pBorrowIndex,
                uint256 poolSupplyIndex,
                uint256 poolBorrowIndex
            ) = lens.getIndexes(markets[marketIndex].poolToken);

            assertEq(expectedIndexes[marketIndex].p2pSupplyIndex, p2pSupplyIndex);
            assertEq(expectedIndexes[marketIndex].p2pBorrowIndex, p2pBorrowIndex);
            assertEq(expectedIndexes[marketIndex].poolSupplyIndex, poolSupplyIndex);
            assertEq(expectedIndexes[marketIndex].poolBorrowIndex, poolBorrowIndex);
        }
    }
}
