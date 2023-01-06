// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestMorphoGetters is TestSetup {
    using WadRayMath for uint256;

    struct UserBalanceStates {
        uint256 collateral;
        uint256 debt;
        uint256 maxDebtValue;
    }

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    function testGetHead() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 10;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        assertEq(address(0), morpho.getHead(aDai, Types.PositionType.SUPPLIERS_IN_P2P));
        assertEq(address(borrower1), morpho.getHead(aDai, Types.PositionType.SUPPLIERS_ON_POOL));
        assertEq(address(0), morpho.getHead(aDai, Types.PositionType.BORROWERS_IN_P2P));
        assertEq(address(0), morpho.getHead(aDai, Types.PositionType.BORROWERS_ON_POOL));

        borrower1.borrow(aDai, toBorrow);

        assertEq(address(borrower1), morpho.getHead(aDai, Types.PositionType.SUPPLIERS_IN_P2P));
        assertEq(address(borrower1), morpho.getHead(aDai, Types.PositionType.SUPPLIERS_ON_POOL));
        assertEq(address(borrower1), morpho.getHead(aDai, Types.PositionType.BORROWERS_IN_P2P));
        assertEq(address(0), morpho.getHead(aDai, Types.PositionType.BORROWERS_ON_POOL));

        borrower1.borrow(aUsdc, to6Decimals(toBorrow));

        assertEq(address(borrower1), morpho.getHead(aUsdc, Types.PositionType.BORROWERS_ON_POOL));
    }

    function testGetNext() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 10);

        uint256 maxSortedUsers = 10;
        morpho.setMaxSortedUsers(maxSortedUsers);
        createSigners(maxSortedUsers);
        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].approve(dai, amount - i);
            borrowers[i].supply(aDai, amount - i);
            borrowers[i].borrow(aUsdc, toBorrow - i);
        }

        address nextSupplyOnPool = address(borrowers[0]);
        address nextBorrowOnPool = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyOnPool = morpho.getNext(
                aDai,
                Types.PositionType.SUPPLIERS_ON_POOL,
                nextSupplyOnPool
            );
            nextBorrowOnPool = morpho.getNext(
                aUsdc,
                Types.PositionType.BORROWERS_ON_POOL,
                nextBorrowOnPool
            );

            assertEq(nextSupplyOnPool, address(borrowers[i + 1]));
            assertEq(nextBorrowOnPool, address(borrowers[i + 1]));
        }

        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].borrow(aDai, (amount / 100) - i);
        }

        for (uint256 i; i < suppliers.length; i++) {
            suppliers[i].approve(usdc, toBorrow - i);
            suppliers[i].supply(aUsdc, toBorrow - i);
        }

        address nextSupplyInP2P = address(suppliers[0]);
        address nextBorrowInP2P = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyInP2P = morpho.getNext(
                aUsdc,
                Types.PositionType.SUPPLIERS_IN_P2P,
                nextSupplyInP2P
            );
            nextBorrowInP2P = morpho.getNext(
                aDai,
                Types.PositionType.BORROWERS_IN_P2P,
                nextBorrowInP2P
            );

            assertEq(address(suppliers[i + 1]), nextSupplyInP2P);
            assertEq(address(borrowers[i + 1]), nextBorrowInP2P);
        }
    }

    function testGetMarketsCreated() public {
        address[] memory marketsCreated = morpho.getMarketsCreated();
        for (uint256 i; i < pools.length; i++) {
            assertEq(marketsCreated[i], pools[i]);
        }
    }
}
