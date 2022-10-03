// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;
    using Math for uint256;

    function testUpgradeLens() public {
        Lens lensImplV2 = new Lens(address(morpho));

        (
            uint256 p2pSupplyIndexBefore,
            uint256 p2pBorrowIndexBefore,
            uint256 poolSupplyIndexBefore,
            uint256 poolBorrowIndexBefore
        ) = lens.getIndexes(aStEth);

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(lensProxy, address(lensImplV2));

        (
            uint256 p2pSupplyIndexAfter,
            uint256 p2pBorrowIndexAfter,
            uint256 poolSupplyIndexAfter,
            uint256 poolBorrowIndexAfter
        ) = lens.getIndexes(aStEth);

        assertEq(p2pSupplyIndexAfter, p2pSupplyIndexBefore);
        assertEq(p2pBorrowIndexAfter, p2pBorrowIndexBefore);
        assertEq(poolSupplyIndexAfter, poolSupplyIndexBefore);
        assertEq(poolBorrowIndexAfter, poolBorrowIndexBefore);
    }
}
