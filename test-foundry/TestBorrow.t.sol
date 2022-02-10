// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/libraries/aave/WadRayMath.sol";

import "./utils/TestSetup.sol";

contract TestBorrow is TestSetup {
    // 2.1 - The user borrows less than the threshold of the given market, the transaction reverts.
    function test_borrow_2_1() public {
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            uint256 amount = positionsManager.threshold(pool) - 1;

            hevm.expectRevert(abi.encodeWithSignature("AmountNotAboveThreshold()"));
            borrower1.borrow(pool, amount);
        }
    }

    // 2.2 - The borrower tries to borrow more than what his collateral allows, the transaction reverts.
    function test_borrow_2_2(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrow.amount =
            getMaxToBorrow(supply.amount, supply.underlying, borrow.underlying) +
            denormalizeAmount(2 ether, borrow.underlying);

        borrower1.supply(supply.poolToken, supply.amount);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.borrow(borrow.poolToken, borrow.amount);
    }

    // Should be able to borrow more ERC20 after already having borrowed ERC20
    function test_borrow_multiple(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.supply(supply.poolToken, 2 * supply.amount);

        (, uint256 onPoolBefore) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        borrower1.borrow(borrow.poolToken, borrow.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            borrow.underlying
        );
        uint256 expectedOnPool = onPoolBefore +
            underlyingToAdUnit(2 * borrow.amount, normalizedVariableDebt);

        assertApproxEq(onPool, expectedOnPool, 2, "borrower1 on pool");
    }

    // 2.3 - There are no available suppliers: all of the borrowed amount is onPool.
    function test_borrow_2_3(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.supply(supply.poolToken, supply.amount);

        borrower1.borrow(borrow.poolToken, borrow.amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 expectedOnPool = underlyingToAdUnit(
            borrow.amount,
            lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
        );

        assertApproxEq(inP2P, 0, 2, "borrower1 in P2P2");
        assertApproxEq(onPool, expectedOnPool, 2, "borrower1 on pool");
    }

    // 2.4 - There is 1 available supplier, he matches 100% of the borrower liquidity, everything is inP2P.
    function test_borrow_2_4(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        supplier1.supply(borrow.poolToken, borrow.amount);

        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedInP2P = underlyingToP2PUnit(
            borrow.amount,
            marketsManager.borrowP2PExchangeRate(borrow.poolToken)
        );

        assertApproxEq(expectedInP2P, borrow.amount, 2, "supplier1 in P2P");

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        assertApproxEq(inP2P, supplyInP2P, 2, "borrower1 in P2P");
        assertApproxEq(onPool, 0, 2, "borrower1 on pool");
    }

    // 2.5 - There is 1 available supplier, he doesn't match 100% of the borrower liquidity.
    // Borrower inP2P is equal to the supplier previous amount onPool, the rest is set onPool.
    function test_borrow_2_5(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        supplier1.supply(borrow.poolToken, borrow.amount);

        borrower1.supply(supply.poolToken, 2 * supply.amount);
        borrower1.borrow(borrow.poolToken, 2 * borrow.amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        (uint256 inP2P, ) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        assertApproxEq(inP2P, supplyInP2P, 2, "borrower1 in P2P");
    }

    // 2.6 - There are NMAX (or less) suppliers that match the borrowed amount, everything is inP2P after NMAX (or less) match.
    function test_borrow_2_6() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / NMAX;

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(inP2P, amount);
        testEquality(onPool, 0);
    }

    // 2.7 - The NMAX biggest suppliers don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set onPool.
    // ⚠️ most gas expensive borrow scenario.
    function test_borrow_2_7() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / (2 * NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));

            expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));

        expectedInP2P = p2pUnitToUnderlying(amount / 2, supplyP2PExchangeRate);
        uint256 expectedOnPool = underlyingToAdUnit(amount / 2, normalizedVariableDebt);

        testEquality(inP2P, expectedInP2P);
        testEquality(onPool, expectedOnPool);
    }
}
