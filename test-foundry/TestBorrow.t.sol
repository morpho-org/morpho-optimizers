// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestBorrow is TestSetup {
    using WadRayMath for uint256;

    // 2.1 - The user borrows less than the threshold of the given market, the transaction reverts.
    function test_borrow_2_1() public {
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            uint256 amount = positionsManager.threshold(pool) - 1;
            borrower1.approve(IAToken(pool).UNDERLYING_ASSET_ADDRESS(), amount);

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
            2 *
            10**(18 - ERC20(borrow.underlying).decimals());
        emit log_named_decimal_uint(
            "borrow.amount",
            borrow.amount,
            ERC20(borrow.underlying).decimals()
        );

        borrower1.approve(supply.underlying, supply.amount);
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

        borrower1.approve(supply.underlying, 2 * supply.amount);
        borrower1.supply(supply.poolToken, 2 * supply.amount);

        borrower1.borrow(borrow.poolToken, borrow.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            borrow.underlying
        );
        uint256 expectedOnPool = underlyingToAdUnit(2 * borrow.amount, normalizedVariableDebt);
        assertEq(onPool, expectedOnPool, "borrower1 on pool");
    }

    // 2.3 - There are no available suppliers: all of the borrowed amount is onPool.
    function test_borrow_2_3(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);

        (, uint256 onPoolBefore) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        borrower1.borrow(borrow.poolToken, borrow.amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            borrow.underlying
        );
        uint256 expectedOnPool = onPoolBefore +
            underlyingToAdUnit(borrow.amount, normalizedVariableDebt);

        assertEq(inP2P, 0, "borrower1 in P2P2");
        assertEqNear(onPool, expectedOnPool, "borrower1 on pool");
    }

    // 2.4 - There is 1 available supplier, he matches 100% of the borrower liquidity, everything is inP2P.
    function test_borrow_2_4(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(borrow.poolToken);
        uint256 expectedInP2P = p2pUnitToUnderlying(supplyInP2P, borrowP2PExchangeRate);

        assertEq(expectedInP2P, borrow.amount, "supplier1 in P2P");

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        assertEq(inP2P, supplyInP2P, "borrower1 in P2P");
        assertEq(onPool, 0, "borrower1 on pool");
    }

    // 2.5 - There is 1 available supplier, he doesn't match 100% of the borrower liquidity.
    // Borrower inP2P is equal to the supplier previous amount onPool, the rest is set onPool.
    function test_borrow_2_5(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        (, uint256 onPoolBefore) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );
        emit log_named_uint("onPoolBefore", onPoolBefore);

        borrower1.approve(supply.underlying, 2 * supply.amount);
        borrower1.supply(supply.poolToken, 2 * supply.amount);
        borrower1.borrow(borrow.poolToken, 2 * borrow.amount);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        assertEq(inP2P, supplyInP2P, "borrower1 in P2P");

        uint256 expectedOnPool = onPoolBefore +
            underlyingToAdUnit(
                borrow.amount,
                lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
            );

        assertEq(onPool, expectedOnPool, "borrower1 on pool");
    }

    // 2.6 - There are NMAX (or less) suppliers that match the borrowed amount, everything is inP2P after NMAX (or less) match.
    function test_borrow_2_6(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        (uint256 inP2Pbefore, ) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(suppliers[0])
        );
        uint256[] memory supplierInP2PBefore = new uint256[](NMAX);
        for (uint256 i = 0; i < NMAX; i++) {
            (supplierInP2PBefore[i], ) = positionsManager.supplyBalanceInOf(
                borrow.poolToken,
                address(suppliers[i])
            );
            suppliers[i].approve(borrow.underlying, borrow.amount);
            suppliers[i].supply(borrow.poolToken, borrow.amount);
        }

        borrower1.approve(supply.underlying, NMAX * supply.amount);
        borrower1.supply(supply.poolToken, NMAX * supply.amount);
        borrower1.borrow(borrow.poolToken, NMAX * borrow.amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(
                borrow.poolToken,
                address(suppliers[i])
            );

            expectedInP2P =
                supplierInP2PBefore[i] +
                underlyingToP2PUnit(borrow.amount, supplyP2PExchangeRate);

            assertEq(inP2P, expectedInP2P, "supplierX in P2P");
            assertEq(onPool, 0, "supplierX on pool");
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(borrow.poolToken, address(borrower1));
        expectedInP2P = underlyingToP2PUnit(
            NMAX * borrow.amount,
            marketsManager.borrowP2PExchangeRate(borrow.poolToken)
        );

        assertEq(inP2P, expectedInP2P, "borrower1 in P2P2");
        assertEq(onPool, 0, "borrower1 on pool");
    }

    // 2.7 - The NMAX biggest suppliers don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set onPool.
    // ⚠️ most gas expensive borrow scenario.
    function test_borrow_2_7(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            (uint256 inP2PBefore, uint256 onPoolBefore) = positionsManager.supplyBalanceInOf(
                borrow.poolToken,
                address(suppliers[i])
            );
            emit log_named_uint("inP2P  before supplierX", inP2PBefore);
            emit log_named_uint("onPool before supplierX", onPoolBefore);
            suppliers[i].approve(borrow.underlying, borrow.amount);
            suppliers[i].supply(borrow.poolToken, borrow.amount);
        }

        borrower1.approve(supply.underlying, 2 * NMAX * supply.amount);
        borrower1.supply(supply.poolToken, 2 * NMAX * supply.amount);
        borrower1.borrow(borrow.poolToken, 2 * NMAX * borrow.amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            borrow.underlying
        );
        uint256 expectedInP2P;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(
                borrow.poolToken,
                address(suppliers[i])
            );

            expectedInP2P = underlyingToP2PUnit(borrow.amount, supplyP2PExchangeRate);

            assertEq(inP2P, expectedInP2P, "supplierX in P2P");
            assertEq(onPool, 0, "supplierX on pool");
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(borrow.poolToken, address(borrower1));

        expectedInP2P = p2pUnitToUnderlying(
            NMAX * borrow.amount,
            marketsManager.borrowP2PExchangeRate(borrow.poolToken)
        );
        uint256 expectedOnPool = underlyingToAdUnit(NMAX * borrow.amount, normalizedVariableDebt);

        assertEq(inP2P, expectedInP2P, "borrower1 in P2P");
        assertEq(onPool, expectedOnPool, "borrower1 on pool");
    }
}
