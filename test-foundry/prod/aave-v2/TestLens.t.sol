// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;
    using Math for uint256;

    struct Vars {
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
    }

    function testUpgradeLens() public {
        Lens lensImplV2 = new Lens(address(morpho));

        address[] memory marketsCreated = lens.getAllMarkets();
        Vars[] memory expectedValues = new Vars[](marketsCreated.length);

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(lensProxy, address(lensImplV2));

        for (uint256 i; i < marketsCreated.length; ++i) {
            address market = marketsCreated[i];
            if (market == aStEth) continue;

            (
                uint256 p2pSupplyIndex,
                uint256 p2pBorrowIndex,
                uint256 poolSupplyIndex,
                uint256 poolBorrowIndex
            ) = lens.getIndexes(market);

            expectedValues[i].p2pSupplyIndex = p2pSupplyIndex;
            expectedValues[i].p2pBorrowIndex = p2pBorrowIndex;
            expectedValues[i].poolSupplyIndex = poolSupplyIndex;
            expectedValues[i].poolBorrowIndex = poolBorrowIndex;
        }

        for (uint256 i; i < marketsCreated.length; ++i) {
            address market = marketsCreated[i];
            if (market == aStEth) continue;

            (
                uint256 p2pSupplyIndex,
                uint256 p2pBorrowIndex,
                uint256 poolSupplyIndex,
                uint256 poolBorrowIndex
            ) = lens.getIndexes(market);

            assertEq(expectedValues[i].p2pSupplyIndex, p2pSupplyIndex);
            assertEq(expectedValues[i].p2pBorrowIndex, p2pBorrowIndex);
            assertEq(expectedValues[i].poolSupplyIndex, poolSupplyIndex);
            assertEq(expectedValues[i].poolBorrowIndex, poolBorrowIndex);
        }
    }
}
