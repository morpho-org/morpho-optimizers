// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/libraries/aave/WadRayMath.sol";

import "./utils/TestSetup.sol";

contract TestMarketStrategy is TestSetup {
    using WadRayMath for uint256;

    function test_borrow_flip_strategy_move_to_pool_borrower_first() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 500 ether;

        // Flip strategy
        marketsManager.setNoP2P(aDai, true);

        borrower1.supply(aUsdc, to6Decimals(amount));

        borrower1.borrow(aDai, toBorrow);

        supplier1.supply(aDai, toBorrow);

        // supplier1 and borrower1 should not be in P2P
        (uint256 borrowInP2P, uint256 borrowOnPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        (uint256 supplyInP2P, uint256 supplyOnPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        assertEq(borrowInP2P, 0);
        assertEq(supplyInP2P, 0);
        assertGt(borrowOnPool, 0);
        assertGt(supplyOnPool, 0);
    }

    function test_borrow_flip_strategy_move_to_pool_supplier_first() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 500 ether;

        // Flip strategy
        marketsManager.setNoP2P(aDai, true);

        supplier1.supply(aDai, toBorrow);

        borrower1.supply(aUsdc, to6Decimals(amount));

        borrower1.borrow(aDai, toBorrow);

        // supplier1 and borrower1 should not be in P2P
        (uint256 borrowInP2P, uint256 borrowOnPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        (uint256 supplyInP2P, uint256 supplyOnPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        assertEq(borrowInP2P, 0);
        assertEq(supplyInP2P, 0);
        assertGt(borrowOnPool, 0);
        assertGt(supplyOnPool, 0);
    }

    function test_borrow_flip_strategy_move_to_pool_borrowers_first() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 100 ether;

        // Flip strategy
        marketsManager.setNoP2P(aDai, true);

        for (uint256 i = 0; i < 3; i++) {
            borrowers[i].supply(aUsdc, to6Decimals(amount));
            borrowers[i].borrow(aDai, toBorrow);
        }

        supplier1.supply(aDai, toBorrow);

        uint256 borrowInP2P;
        uint256 borrowOnPool;

        for (uint256 i = 0; i < 3; i++) {
            (borrowInP2P, borrowOnPool) = positionsManager.borrowBalanceInOf(
                aDai,
                address(borrowers[i])
            );
            assertEq(borrowInP2P, 0);
            assertGt(borrowOnPool, 0);
        }

        (uint256 supplyInP2P, uint256 supplyOnPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        assertEq(supplyInP2P, 0);
        assertGt(supplyOnPool, 0);
    }

    function test_borrow_flip_strategy_move_to_pool_suppliers_first() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 400 ether;
        uint256 toSupply = 100 ether;

        // Flip strategy
        marketsManager.setNoP2P(aDai, true);

        for (uint256 i = 0; i < 3; i++) {
            suppliers[i].supply(aDai, toSupply);
        }

        borrower1.supply(aUsdc, to6Decimals(amount));

        borrower1.borrow(aDai, toBorrow);

        uint256 supplyInP2P;
        uint256 supplyOnPool;

        for (uint256 i = 0; i < 3; i++) {
            (supplyInP2P, supplyOnPool) = positionsManager.supplyBalanceInOf(
                aDai,
                address(suppliers[i])
            );
            assertEq(supplyInP2P, 0);
            assertGt(supplyOnPool, 0);
        }

        (uint256 borrowInP2P, uint256 borrowOnPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(borrowInP2P, 0);
        assertGt(borrowOnPool, 0);
    }
}
