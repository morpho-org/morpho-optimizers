// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestMarketStrategy is TestSetup {
    function testShouldPutBorrowerOnPool() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = 500 ether;

        morpho.setIsP2PDisabled(aDai, true);

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));

        borrower1.borrow(aDai, toBorrow);

        supplier1.approve(dai, toBorrow);
        supplier1.supply(aDai, toBorrow);

        // supplier1 and borrower1 should not be in peer-to-peer
        (uint256 borrowInP2P, uint256 borrowOnPool) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        (uint256 supplyInP2P, uint256 supplyOnPool) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        assertEq(borrowInP2P, 0);
        assertEq(supplyInP2P, 0);
        assertGt(borrowOnPool, 0);
        assertGt(supplyOnPool, 0);
    }

    function testShouldPutSupplierOnPool() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = 500 ether;

        morpho.setIsP2PDisabled(aDai, true);

        supplier1.approve(dai, toBorrow);
        supplier1.supply(aDai, toBorrow);

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));

        borrower1.borrow(aDai, toBorrow);

        // supplier1 and borrower1 should not be in peer-to-peer
        (uint256 borrowInP2P, uint256 borrowOnPool) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        (uint256 supplyInP2P, uint256 supplyOnPool) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        assertEq(borrowInP2P, 0);
        assertEq(supplyInP2P, 0);
        assertGt(borrowOnPool, 0);
        assertGt(supplyOnPool, 0);
    }

    function testShouldPutBorrowersOnPool() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = 100 ether;

        morpho.setIsP2PDisabled(aDai, true);

        for (uint256 i = 0; i < 3; i++) {
            borrowers[i].approve(usdc, to6Decimals(amount));
            borrowers[i].supply(aUsdc, to6Decimals(amount));
            borrowers[i].borrow(aDai, toBorrow);
        }

        supplier1.approve(dai, toBorrow);
        supplier1.supply(aDai, toBorrow);

        uint256 borrowInP2P;
        uint256 borrowOnPool;

        for (uint256 i = 0; i < 3; i++) {
            (borrowInP2P, borrowOnPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));
            assertEq(borrowInP2P, 0);
            assertGt(borrowOnPool, 0);
        }

        (uint256 supplyInP2P, uint256 supplyOnPool) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        assertEq(supplyInP2P, 0);
        assertGt(supplyOnPool, 0);
    }

    function testShouldPutSuppliersOnPool() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = 400 ether;
        uint256 toSupply = 100 ether;

        morpho.setIsP2PDisabled(aDai, true);

        for (uint256 i = 0; i < 3; i++) {
            suppliers[i].approve(dai, toSupply);
            suppliers[i].supply(aDai, toSupply);
        }

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));

        borrower1.borrow(aDai, toBorrow);

        uint256 supplyInP2P;
        uint256 supplyOnPool;

        for (uint256 i = 0; i < 3; i++) {
            (supplyInP2P, supplyOnPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));
            assertEq(supplyInP2P, 0);
            assertGt(supplyOnPool, 0);
        }

        (uint256 borrowInP2P, uint256 borrowOnPool) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(borrowInP2P, 0);
        assertGt(borrowOnPool, 0);
    }
}
