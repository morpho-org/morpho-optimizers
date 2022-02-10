// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";
import "./utils/Attacker.sol";

contract TestWithdraw is TestSetup {
    // 3.1 - The user withdrawal leads to an under-collateralized position, the withdrawal reverts.
    function test_withdraw_3_1(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        borrower1.supply(supply.poolToken, supply.amount);

        borrower1.borrow(borrow.poolToken, borrow.amount);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.withdraw(supply.poolToken, supply.amount);
    }

    // 3.2 - The supplier withdraws less than his onPool balance. The liquidity is taken from his onPool balance.
    function test_withdraw_3_2(uint128 _amount, uint8 _supplyAsset) public {
        Asset memory supply = getSupplyAsset(_amount, _supplyAsset, true);

        (, uint256 onPoolBefore) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(supplier1)
        );

        supplier1.supply(supply.poolToken, supply.amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            supply.amount,
            lendingPool.getReserveNormalizedIncome(supply.underlying)
        );

        assertEq(inP2P, 0, "supplier1 in P2P before withdraw");
        assertApproxEq(
            onPool,
            onPoolBefore + expectedOnPool,
            2,
            "supplier1 on pool before withdraw"
        );

        supplier1.withdraw(supply.poolToken, supply.amount / 2);

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(supply.poolToken, address(supplier1));

        assertEq(inP2P, 0, "supplier1 in P2P");
        assertApproxEq(onPool, onPoolBefore + expectedOnPool / 2, 2, "supplier1 on pool");
    }

    // 3.3 - The supplier withdraws more than his onPool balance

    // 3.3.1 - There is a supplier onPool available to replace him inP2P.
    // First, his liquidity onPool is taken, his matched is replaced by the available supplier up to his withdrawal amount.
    function test_withdraw_3_3_1(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        (, uint256 onPoolSupplierBefore) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        supplier1.supply(borrow.poolToken, 2 * borrow.amount);

        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        emit log_named_uint("inP2PSupplier", inP2PSupplier);
        emit log_named_uint("onPoolSupplier", onPoolSupplier);

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        emit log_named_uint("inP2PBorrower", inP2PSupplier);
        emit log_named_uint("onPoolBorrower", onPoolSupplier);

        uint256 expectedOnPool = onPoolSupplierBefore +
            underlyingToScaledBalance(
                borrow.amount,
                lendingPool.getReserveNormalizedIncome(borrow.underlying)
            );

        assertApproxEq(onPoolSupplier, expectedOnPool, 2, "supplier1 on pool");
        assertEq(onPoolBorrower, 0, "borrower1 on pool");
        assertEq(inP2PSupplier, inP2PBorrower, "supplier1/borrower1 in P2P");

        // An available supplier onPool
        supplier2.supply(borrow.poolToken, 2 * borrow.amount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(borrow.poolToken, 2 * borrow.amount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );
        assertApproxEq(onPoolSupplier, 0, 2, "supplier1 on pool after withdraw");
        assertApproxEq(inP2PSupplier, 0, 2, "supplier1 in P2P after withdraw");

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier2)
        );
        uint256 expectedInP2P = underlyingToP2PUnit(
            borrow.amount,
            marketsManager.supplyP2PExchangeRate(borrow.poolToken)
        );
        assertApproxEq(onPoolSupplier, expectedOnPool, 2, "supplier2 on pool");
        assertApproxEq(inP2PSupplier, expectedInP2P, 2, "supplier2 in P2P");

        // Check balances for borrower1
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );
        assertEq(onPoolBorrower, 0, "borrower1 on pool");
        assertApproxEq(inP2PSupplier, inP2PBorrower, 2, "borrower1 in P2P");
    }

    // 3.3.2 - There are NMAX (or less) suppliers onPool available to replace him inP2P, they supply enough to cover for the withdrawn liquidity.
    // First, his liquidity onPool is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
    function test_withdraw_3_3_2() public {
        uint256 borrowedAmount = 100000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (NMAX - 1);
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount,
            supplyP2PExchangeRate
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, 0);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }
    }

    // 3.3.3 - There are no suppliers onPool to replace him inP2P. After withdrawing the amount onPool,
    // his P2P match(es) will be unmatched and the corresponding borrower(s) will be placed on pool.
    function test_withdraw_3_3_3(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        //(Asset memory supply, Asset memory borrow) = getAssets(10_000 ether, 1, 0);
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        // Borrower1 & supplier1 are matched for borrow.amount
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        (, uint256 onPoolSupplierBefore) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        supplier1.supply(borrow.poolToken, 2 * borrow.amount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = onPoolSupplierBefore +
            underlyingToScaledBalance(
                borrow.amount,
                lendingPool.getReserveNormalizedIncome(borrow.underlying)
            );

        assertApproxEq(onPoolSupplier, expectedOnPool, 2, "supplier 1 on pool");
        assertApproxEq(onPoolBorrower, 0, 2, "borrower1 on pool");
        assertApproxEq(inP2PSupplier, inP2PBorrower, 2, "supplier1/borrower in P2P");

        // Supplier1 withdraws 75% of supplied amount
        supplier1.withdraw(borrow.poolToken, (75 * 2 * borrow.amount) / 100);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrow.amount / 2,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrow.amount / 2,
            lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
        );

        assertApproxEq(
            inP2PBorrower,
            expectedBorrowBalanceInP2P,
            2,
            "borrower1 in P2P after withraw"
        );
        assertApproxEq(
            onPoolBorrower,
            expectedBorrowBalanceOnPool,
            2,
            "borrower1 on pool after withdraw"
        );

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            (25 * 2 * borrow.amount) / 100,
            supplyP2PExchangeRate
        );

        assertApproxEq(
            inP2PSupplier,
            expectedSupplyBalanceInP2P,
            2,
            "supplier1 in P2P after withdraw"
        );
        assertApproxEq(onPoolSupplier, 0, 2, "supplier1 on pool after withdraw");
    }

    // 3.3.4 - The supplier is matched to 2*NMAX borrowers. There are NMAX suppliers `onPool` available to replace him `inP2P`,
    //         they don't supply enough to cover the withdrawn liquidity.
    //         First, the `onPool` liquidity is withdrawn, then we proceed to NMAX `match supplier`.
    //         Finally, we proceed to NMAX `unmatch borrower` for an amount equal to the remaining to withdraw.
    //         ⚠️ most gas expensive withdraw scenario.
    function test_withdraw_3_3_4() public {
        uint256 borrowedAmount = 100000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint8 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (NMAX - 1));
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount / 2,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowedAmount / 2,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
            testEquality(inP2P, 0);
        }
    }

    // Test attack
    // Should not be possible to withdraw amount if the position turns to be under-collateralized
    function test_withdraw_if_under_collaterize(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        // supplier1 deposits collateral
        supplier1.supply(supply.poolToken, supply.amount);

        // supplier2 deposits collateral
        supplier2.supply(supply.poolToken, supply.amount);

        // supplier1 tries to withdraw more than allowed
        supplier1.borrow(borrow.poolToken, borrow.amount);
        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        supplier1.withdraw(supply.poolToken, supply.amount);
    }

    // Test attack
    // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    function test_withdraw_while_attacker_sends_atoken(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        Attacker attacker = new Attacker(lendingPool);
        writeBalanceOf(address(attacker), borrow.underlying, type(uint256).max / 2);

        // attacker sends aToken to positionsManager contract
        attacker.approve(borrow.underlying, address(lendingPool), borrow.amount);
        attacker.deposit(borrow.underlying, borrow.amount, address(attacker), 0);
        attacker.transfer(borrow.underlying, address(positionsManager), borrow.amount);

        // supplier1 deposits collateral
        supplier1.supply(borrow.poolToken, borrow.amount);

        // borrower1 deposits collateral
        borrower1.supply(supply.poolToken, supply.amount);

        // supplier1 tries to withdraw
        borrower1.borrow(borrow.poolToken, borrow.amount);
        supplier1.withdraw(borrow.poolToken, borrow.amount);
    }
}
