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

        borrower1.approve(supply.underlying, supply.amount);
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

        supplier1.approve(supply.underlying, supply.amount);
        supplier1.supply(supply.poolToken, supply.amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            supply.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            supply.amount,
            lendingPool.getReserveNormalizedIncome(supply.underlying)
        );

        assertEq(inP2P, 0, "supplier1 in P2P");
        assertEq(onPool, onPoolBefore + expectedOnPool, "supplier1 on pool");

        supplier1.withdraw(supply.poolToken, supply.amount / 2);

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(supply.poolToken, address(supplier1));

        assertEq(inP2P, 0, "supplier1 in P2P");
        assertEq(onPool, onPoolBefore + expectedOnPool / 2, "supplier1 on pool");
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

        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            borrow.amount,
            lendingPool.getReserveNormalizedIncome(borrow.underlying)
        );

        assertEq(onPoolSupplier, expectedOnPool, "supplier1 on pool");
        assertEq(onPoolBorrower1, 0, "borrower1 on pool");
        assertEq(inP2PSupplier, inP2PBorrower1, "supplier1/borrower1 in P2P");

        // An available supplier onPool
        supplier2.approve(borrow.underlying, borrow.amount);
        supplier2.supply(borrow.poolToken, borrow.amount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(borrow.poolToken, borrow.amount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );
        assertEq(onPoolSupplier, 0, "supplier1 on pool after withdraw");
        assertEq(inP2PSupplier, 0, "supplier1 in P2P after withdraw");

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier2)
        );
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 expectedInP2P = underlyingToP2PUnit(borrow.amount, supplyP2PExchangeRate);
        assertEq(onPoolSupplier, expectedOnPool, "supplier2 on pool");
        assertEq(inP2PSupplier, expectedInP2P, "supplier2 in P2P");

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );
        assertEq(onPoolBorrower1, 0, "borrower1 on pool");
        assertEq(inP2PSupplier, inP2PBorrower1, "borrower1 in P2P");
    }

    // 3.3.2 - There are NMAX (or less) suppliers onPool available to replace him inP2P, they supply enough to cover for the withdrawn liquidity.
    // First, his liquidity onPool is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
    function test_withdraw_3_3_2(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            borrow.amount,
            lendingPool.getReserveNormalizedIncome(borrow.underlying)
        );

        assertEq(onPoolSupplier, expectedOnPool, "supplier1 on pool");
        assertEq(onPoolBorrower, 0, "borrower1 on pool");
        assertEq(inP2PSupplier, inP2PBorrower, "supplier1/borrower1 in P2P");

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        for (uint256 i = 1; i < NMAX; i++) {
            suppliers[i].approve(borrow.underlying, borrow.amount);
            suppliers[i].supply(borrow.poolToken, borrow.amount);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(borrow.poolToken, NMAX * borrow.amount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );
        assertEq(onPoolSupplier, 0, "supplier1 on pool after withdraw");
        assertEq(inP2PSupplier, 0, "supplier1 in P2P after withdraw");

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrow.amount,
            supplyP2PExchangeRate
        );

        assertEq(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower1 in P2P after withdraw");
        assertEq(onPoolBorrower, 0, "borrower1 on pool after withdraw");

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 1; i < suppliers.length; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(
                borrow.poolToken,
                address(suppliers[i])
            );
            uint256 expectedInP2P = underlyingToP2PUnit(borrow.amount, supplyP2PExchangeRate);

            assertEq(inP2P, expectedInP2P, "supplierX in P2P");
            assertEq(onPool, 0, "supplierX on pool");
        }
    }

    // 3.3.3 - There are no suppliers onPool to replace him inP2P. After withdrawing the amount onPool,
    // his P2P match(es) will be unmatched and the corresponding borrower(s) will be placed on pool.
    function test_withdraw_3_3_3(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        // Borrower1 & supplier1 are matched for borrow.amount
        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);
        borrower1.borrow(borrow.poolToken, borrow.amount);

        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            borrow.amount,
            lendingPool.getReserveNormalizedIncome(borrow.underlying)
        );

        assertEq(onPoolSupplier, expectedOnPool);
        assertEq(onPoolBorrower, 0);
        assertEq(inP2PSupplier, inP2PBorrower);

        // Supplier1 withdraws 75% of supplied amount
        supplier1.withdraw(borrow.poolToken, (75 * borrow.amount) / 100);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrow.amount,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrow.amount,
            lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
        );

        assertEq(inP2PBorrower, expectedBorrowBalanceInP2P);
        assertEq(onPoolBorrower, expectedBorrowBalanceOnPool);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            (25 * borrow.amount) / 100,
            supplyP2PExchangeRate
        );

        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P);
        assertEq(onPoolSupplier, 0);
    }

    // 3.3.4 - There are NMAX (or less) suppliers onPool available to replace him inP2P, they don't supply enough to cover the withdrawn liquidity.
    // First, the onPool liquidity is withdrawn, then we proceed to NMAX (or less) matches. Finally, some borrowers are unmatched for an amount equal to the remaining to withdraw.
    // ⚠️ most gas expensive withdraw scenario.
    function test_withdraw_3_3_4(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        // Borrower1 & supplier1 are matched for borrow.amount
        borrower1.approve(supply.underlying, 2 * supply.amount);
        borrower1.supply(supply.poolToken, 2 * supply.amount);
        borrower1.borrow(borrow.poolToken, 2 * borrow.amount);

        supplier1.approve(borrow.underlying, 2 * borrow.amount);
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

        uint256 expectedOnPool = underlyingToScaledBalance(
            borrow.amount,
            lendingPool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        for (uint256 i = 1; i < NMAX; i++) {
            suppliers[i].approve(borrow.underlying, borrow.amount);
            suppliers[i].supply(borrow.poolToken, borrow.amount);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(borrow.poolToken, borrow.amount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            borrow.poolToken,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            borrow.poolToken,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(borrow.poolToken);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrow.amount,
            supplyP2PExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrow.amount,
            lendingPool.getReserveNormalizedVariableDebt(borrow.underlying)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool);

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(
                borrow.poolToken,
                address(suppliers[i])
            );
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, borrow.amount);
            testEquality(onPool, 0);

            (inP2P, onPool) = positionsManager.borrowBalanceInOf(
                borrow.poolToken,
                address(borrowers[i])
            );
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
        supplier1.approve(supply.underlying, supply.amount);
        supplier1.supply(supply.poolToken, supply.amount);

        // supplier2 deposits collateral
        supplier2.approve(supply.underlying, supply.amount);
        supplier2.supply(supply.poolToken, supply.amount);

        // supplier1 tries to withdraw more than allowed
        supplier1.borrow(borrow.poolToken, borrow.amount);
        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        supplier1.withdraw(supply.poolToken, supply.amount);
    }

    // Test attack
    // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    function test_withdraw_while_attacker_sends_AToken(
        uint128 _amount,
        uint8 _supplyAsset,
        uint8 _borrowAsset
    ) public {
        (Asset memory supply, Asset memory borrow) = getAssets(_amount, _supplyAsset, _borrowAsset);

        Attacker attacker = new Attacker(lendingPool);
        writeBalanceOf(address(attacker), dai, type(uint256).max / 2);

        // attacker sends aToken to positionsManager contract
        attacker.approve(borrow.underlying, address(lendingPool), borrow.amount);
        attacker.deposit(borrow.underlying, borrow.amount, address(attacker), 0);
        attacker.transfer(borrow.underlying, address(positionsManager), borrow.amount);

        // supplier1 deposits collateral
        supplier1.approve(borrow.underlying, borrow.amount);
        supplier1.supply(borrow.poolToken, borrow.amount);

        // borrower1 deposits collateral
        borrower1.approve(supply.underlying, supply.amount);
        borrower1.supply(supply.poolToken, supply.amount);

        // supplier1 tries to withdraw
        borrower1.borrow(borrow.poolToken, borrow.amount);
        supplier1.withdraw(borrow.poolToken, borrow.amount);
    }
}
