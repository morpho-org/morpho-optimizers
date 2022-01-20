// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestSupply is TestSetup {
    // 1.1 - The user supplies less than the threshold of this market, the transaction reverts.
    function test_supply_1_1() public {
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            uint256 amount = positionsManager.threshold(pool) - 1;
            supplier1.approve(IAToken(pool).UNDERLYING_ASSET_ADDRESS(), amount);

            hevm.expectRevert(abi.encodeWithSignature("AmountNotAboveThreshold()"));
            supplier1.supply(pool, amount);
        }
    }

    // 1.2 - There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.
    function test_supply_1_2(uint256 _amount, uint8 _supplyAsset) public {
        Asset memory supply = getSupplyAsset(_amount, _supplyAsset, true);

        uint256 morphoBefore = IERC20(supply.poolToken).balanceOf(address(positionsManager));
        (, uint256 onPoolBefore) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(supplier1)
        );

        supplier1.approve(supply.underlying, supply.amount);
        supplier1.supply(supply.poolToken, supply.amount);

        uint256 morphoAfter = IERC20(supply.poolToken).balanceOf(address(positionsManager));
        assertEq(morphoAfter - morphoBefore, supply.amount, "positionsManager balance");

        marketsManager.updateRates(supply.poolToken);
        uint256 expectedOnPool = onPoolBefore +
            underlyingToScaledBalance(
                supply.amount,
                lendingPool.getReserveNormalizedIncome(supply.underlying)
            );

        (uint256 inP2PAfter, uint256 onPoolAfter) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(supplier1)
        );

        assertEqNear(onPoolAfter, expectedOnPool, "supplier on pool");
        assertEq(inP2PAfter, 0, "supplier1 in P2P");
    }

    // Should be able to supply more ERC20 after already having supply ERC20
    function test_supply_multiple(uint256 _amount, uint8 _supplyAsset) public {
        Asset memory supply = getSupplyAsset(_amount, _supplyAsset, true);

        (, uint256 onPoolBefore) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(supplier1)
        );

        supplier1.approve(supply.underlying, 2 * supply.amount);

        supplier1.supply(supply.poolToken, supply.amount);
        supplier1.supply(supply.poolToken, supply.amount);

        (, uint256 onPoolAfter) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(supplier1)
        );

        marketsManager.updateRates(supply.poolToken);
        uint256 expectedOnPool = onPoolBefore +
            underlyingToScaledBalance(
                2 * supply.amount,
                lendingPool.getReserveNormalizedIncome(supply.underlying)
            );

        assertEqNear(onPoolAfter, expectedOnPool, "supplier1 on pool");
    }

    // 1.3 - There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.
    function test_supply_1_3(
        uint256 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        supply.amount *= 2;
        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);

        emit log_named_decimal_uint(
            "supply.amount",
            supply.amount,
            ERC20(supply.underlying).decimals()
        );
        emit log_named_decimal_uint(
            "borrow.amount",
            borrow.amount,
            ERC20(borrow.underlying).decimals()
        );
        borrower1.borrow(borrow.poolToken, borrow.amount);

        uint256 daiBalanceBefore = supplier1.balanceOf(borrow.underlying);

        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(borrow.underlying);
        assertEq(daiBalanceAfter, daiBalanceBefore - borrow.amount, "supplier1 dai balance");

        marketsManager.updateRates(borrow.poolToken);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            borrow.amount,
            marketsManager.supplyP2PExchangeRate(borrow.poolToken)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "supplier1 in P2P");
        assertEq(onPoolSupplier, 0, "supplier1 on pool");

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );
        assertEq(inP2PBorrower, inP2PSupplier, "borrower1 in P2P");
        assertEq(onPoolBorrower, 0, "borrower1 on pool");
    }

    // 1.4 - There is 1 available borrower, he doesn't match 100% of the supplier liquidity.
    // Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.
    function test_supply_1_4(
        uint256 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.approve(supply.underlying, 2 * supply.amount);
        borrower1.supply(supply.poolToken, 2 * supply.amount);

        borrower1.borrow(borrow.poolToken, borrow.amount);

        supplier1.approve(borrow.underlying, 2 * borrow.amount);
        supplier1.supply(borrow.poolToken, 2 * borrow.amount);

        marketsManager.updateRates(borrow.poolToken);
        (uint256 inP2PSupplier, ) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );
        assertEq(inP2PBorrower, inP2PSupplier, "borrower1 in P2P");
        assertEq(onPoolBorrower, 0, "borrower1 on pool");
    }

    // 1.5 - There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.
    function test_supply_1_5(
        uint256 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(supply.underlying, 2 * supply.amount);
            borrowers[i].supply(supply.poolToken, 2 * supply.amount);

            borrowers[i].borrow(borrow.poolToken, borrow.amount);
        }

        supplier1.approve(borrow.underlying, NMAX * borrow.amount);
        supplier1.supply(borrow.poolToken, NMAX * borrow.amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 expectedInP2P;
        uint256 p2pExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(
                borrow.poolToken,
                address(borrowers[i])
            );

            expectedInP2P = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertEq(expectedInP2P, borrow.amount, "borrower1 in P2P");
            assertEq(onPool, 0, "borrower1 on pool");
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(borrow.poolToken, address(supplier1));
        expectedInP2P = p2pUnitToUnderlying(NMAX * borrow.amount, p2pExchangeRate);

        assertEq(inP2P, expectedInP2P, "supplier1 in P2P");
        assertEq(onPool, 0, "supplier1 on pool");
    }

    // 1.6 - The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`.
    // ⚠️ most gas expensive supply scenario.
    function test_supply_1_6(
        uint256 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        uint256 amount = 10_000 ether;
        uint256 amountPerBorrower = amount / (2 * NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(supply.underlying, 2 * supply.amount);
            borrowers[i].supply(supply.poolToken, 2 * supply.amount);

            borrowers[i].borrow(borrow.poolToken, amountPerBorrower);
        }

        supplier1.approve(borrow.underlying, amount);
        supplier1.supply(borrow.poolToken, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 expectedInP2P;
        uint256 p2pExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(borrow.underlying);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(
                borrow.poolToken,
                address(borrowers[i])
            );

            expectedInP2P = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertEq(expectedInP2P, amountPerBorrower, "borrower in P2P");
            assertEq(onPool, 0, "borrower on pool");
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(borrow.poolToken, address(supplier1));

        expectedInP2P = p2pUnitToUnderlying(amount / 2, p2pExchangeRate);
        uint256 expectedOnPool = underlyingToAdUnit(amount / 2, normalizedIncome);

        assertEq(inP2P, expectedInP2P, "supplier1 in P2P");
        assertEq(onPool, expectedOnPool, "supplier1 on pool");
    }
}
