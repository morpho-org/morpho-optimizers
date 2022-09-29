// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {Attacker} from "./helpers/Attacker.sol";
import "./setup/TestSetup.sol";

contract TestWithdraw is TestSetup {
    using WadRayMath for uint256;

    // The user withdrawal leads to an under-collateralized position, the withdrawal reverts.
    function testWithdraw1() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        borrower1.borrow(aDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedWithdraw()"));
        borrower1.withdraw(aUsdc, to6Decimals(collateral));
    }

    // The supplier withdraws less than his `onPool` balance. The liquidity is taken from his `onPool` balance.
    function testWithdraw2() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(aUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(
            underlyingToScaledBalance(2 * amount, pool.getReserveNormalizedIncome(usdc))
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (inP2P, onPool) = morpho.supplyBalanceInOf(aUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool / 2);
    }

    // The supplier withdraws all its `onPool` balance.
    function testWithdrawAll() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        uint256 balanceBefore = supplier1.balanceOf(usdc);
        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(
            underlyingToScaledBalance(amount, pool.getReserveNormalizedIncome(usdc))
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(aUsdc, type(uint256).max);

        uint256 balanceAfter = supplier1.balanceOf(usdc);
        (inP2P, onPool) = morpho.supplyBalanceInOf(aUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
        testEquality(balanceAfter - balanceBefore, to6Decimals(amount));
    }

    // There is a supplier `onPool` available to replace him `inP2P`. First, his liquidity `onPool` is taken, his matched is replaced by the available supplier up to his withdrawal amount.
    function testWithdraw3_1() public {
        uint256 borrowedAmount = 10_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            pool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool, "supplier on pool 0");
        testEquality(onPoolBorrower1, 0, "borrower on pool 0");
        testEquality(inP2PSupplier, inP2PBorrower1, "matched");

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(aDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        testEquality(onPoolSupplier, 0, "supplier on pool 1");
        testEquality(inP2PSupplier, 0, "supplier in P2P 1");

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier2));
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedInP2P = underlyingToP2PUnit(suppliedAmount / 2, p2pSupplyIndex);
        testEquality(onPoolSupplier, expectedOnPool, "supplier on pool 2");
        testEquality(inP2PSupplier, expectedInP2P, "supplier in P2P 2");

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(aDai, address(borrower1));
        testEquality(onPoolBorrower1, 0, "borrower on pool 1");
        testEquality(inP2PSupplier, inP2PBorrower1, "borrower in P2P 1");
    }

    // There are NMAX (or less) suppliers `onPool` available to replace him `inP2P`, they supply enough to cover for the withdrawn liquidity. First, his liquidity `onPool` is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
    function testWithdraw3_2() public {
        // TODO: fix this.
        deal(dai, address(morpho), 1);

        _setDefaultMaxGasForMatching(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            pool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool, "supplier on pool");
        testEquality(onPoolBorrower, 0, "borrower on pool");
        testEquality(inP2PSupplier, inP2PBorrower, "equality");

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (NMAX - 1);
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        testEquality(onPoolSupplier, 0, "supplier on pool");
        testEquality(inP2PSupplier, 0, "supplier in P2P");

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount,
            morpho.p2pBorrowIndex(aDai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in P2P");
        testEquality(onPoolBorrower, 0, "borrower on pool");

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, p2pSupplyIndex);

            testEquality(expectedInP2P, amountPerSupplier, "new supplier in P2P");
            testEquality(onPool, 0, "new supplier on pool");
        }
    }

    // There are no suppliers `onPool` to replace him `inP2P`. After withdrawing the amount `onPool`, his peer-to-peer credit lines will be broken and the corresponding borrower(s) will be unmatched and placed on pool.
    function testWithdraw3_3() public {
        uint256 borrowedAmount = 10_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            pool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool, "supplier on pool");
        testEquality(onPoolBorrower, 0, "borrower on pool");
        testEquality(inP2PSupplier, inP2PBorrower, "equality P2P");

        // Supplier1 withdraws 75% of supplied amount
        supplier1.withdraw(aDai, (75 * suppliedAmount) / 100);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount / 2,
            p2pSupplyIndex
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowedAmount / 2,
            pool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in P2P");
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool, "borrower in pool 2");

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(
            (25 * suppliedAmount) / 100,
            p2pSupplyIndex
        );

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, 0);
    }

    // The supplier is matched to 2 x NMAX borrowers. There are NMAX suppliers `onPool` available to replace him `inP2P`, they don't supply enough to cover the withdrawn liquidity. First, the `onPool` liquidity is withdrawn, then we proceed to NMAX `match supplier`. Finally, we proceed to NMAX `unmatch borrower` for an amount equal to the remaining to withdraw.
    function testWithdraw3_4() public {
        // TODO: fix that.
        deal(dai, address(morpho), 1 ether);

        _setDefaultMaxGasForMatching(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToScaledBalance(
            suppliedAmount / 2,
            pool.getReserveNormalizedIncome(dai)
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (NMAX - 1));
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount
        supplier1.withdraw(aDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        testEquality(onPoolSupplier, 0, "supplier on pool");
        testEquality(inP2PSupplier, 0, "supplier in P2P");

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            borrowedAmount / 2,
            p2pSupplyIndex
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowedAmount / 2,
            pool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in P2P");
        testEquality(onPoolBorrower, expectedBorrowBalanceOnPool, "borrower on pool");

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, p2pSupplyIndex);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);

            (inP2P, onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));
            testEquality(inP2P, 0);
        }
    }

    struct Vars {
        uint256 LR;
        uint256 APR;
        uint256 VBR;
        uint256 NVD;
        uint256 BP2PD;
        uint256 BP2PA;
        uint256 BP2PER;
    }

    function testDeltaWithdraw() public {
        // Allows only 10 unmatch borrowers
        _setDefaultMaxGasForMatching(3e6, 3e6, 1.2e6, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount + 7;
        uint256 expectedSupplyBalanceInP2P;

        // supplier1 and 20 borrowers are matched for suppliedAmount
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        createSigners(30);

        // 2 * NMAX borrowers borrow borrowedAmount
        for (uint256 i; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, borrowedAmount, type(uint64).max);
        }

        {
            uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
            expectedSupplyBalanceInP2P = underlyingToP2PUnit(suppliedAmount, p2pSupplyIndex);

            // Check balances after match of supplier1 and borrowers
            (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
                aDai,
                address(supplier1)
            );
            testEquality(onPoolSupplier, 0);
            testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);

            uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
            uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
                borrowedAmount,
                p2pBorrowIndex
            );

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
                    aDai,
                    address(borrowers[i])
                );
                testEquality(onPoolBorrower, 0);
                testEquality(inP2PBorrower, expectedBorrowBalanceInP2P);
            }

            // Supplier withdraws max
            // Should create a delta on borrowers side
            supplier1.withdraw(aDai, type(uint256).max);

            // Check balances for supplier1
            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));
            testEquality(onPoolSupplier, 0);
            testEquality(inP2PSupplier, 0);

            // There should be a delta
            uint256 expectedBorrowP2PDeltaInUnderlying = 10 * borrowedAmount;
            uint256 expectedBorrowP2PDelta = underlyingToAdUnit(
                expectedBorrowP2PDeltaInUnderlying,
                pool.getReserveNormalizedVariableDebt(dai)
            );

            (, uint256 borrowP2PDelta, , ) = morpho.deltas(aDai);
            testEquality(borrowP2PDelta, expectedBorrowP2PDelta, "borrow Delta not expected 1");

            // Borrow delta matching by new supplier
            supplier2.approve(dai, expectedBorrowP2PDeltaInUnderlying / 2);
            supplier2.supply(aDai, expectedBorrowP2PDeltaInUnderlying / 2);

            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier2));
            expectedSupplyBalanceInP2P = underlyingToP2PUnit(
                expectedBorrowP2PDeltaInUnderlying / 2,
                p2pSupplyIndex
            );

            (, borrowP2PDelta, , ) = morpho.deltas(aDai);
            testEquality(borrowP2PDelta, expectedBorrowP2PDelta / 2, "borrow Delta not expected 2");
            testEquality(onPoolSupplier, 0, "on pool supplier not 0");
            testEquality(
                inP2PSupplier,
                expectedSupplyBalanceInP2P,
                "in peer-to-peer supplier not expected"
            );
        }

        {
            Vars memory oldVars;
            Vars memory newVars;

            (, oldVars.BP2PD, , oldVars.BP2PA) = morpho.deltas(aDai);
            oldVars.NVD = pool.getReserveNormalizedVariableDebt(dai);
            oldVars.BP2PER = morpho.p2pBorrowIndex(aDai);
            (, oldVars.APR) = getApproxP2PRates(aDai);

            move1YearForward(aDai);

            (, newVars.BP2PD, , newVars.BP2PA) = morpho.deltas(aDai);
            newVars.NVD = pool.getReserveNormalizedVariableDebt(dai);
            newVars.BP2PER = morpho.p2pBorrowIndex(aDai);
            newVars.LR = pool.getReserveData(dai).currentLiquidityRate;
            newVars.VBR = pool.getReserveData(dai).currentVariableBorrowRate;

            uint256 shareOfTheDelta = newVars
            .BP2PD
            .wadToRay()
            .rayMul(newVars.NVD)
            .rayDiv(oldVars.BP2PER)
            .rayDiv(newVars.BP2PA.wadToRay());

            uint256 expectedBP2PER = oldVars.BP2PER.rayMul(
                computeCompoundedInterest(oldVars.APR, 365 days).rayMul(RAY - shareOfTheDelta) +
                    shareOfTheDelta.rayMul(newVars.NVD).rayDiv(oldVars.NVD)
            );

            assertApproxEqAbs(
                expectedBP2PER,
                newVars.BP2PER,
                (expectedBP2PER * 2) / 100,
                "BP2PER not expected"
            );

            uint256 expectedBorrowBalanceInUnderlying = borrowedAmount
            .rayDiv(oldVars.BP2PER)
            .rayMul(expectedBP2PER);

            for (uint256 i = 1; i <= 10; i++) {
                (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
                    aDai,
                    address(borrowers[i])
                );
                assertApproxEqAbs(
                    p2pUnitToUnderlying(inP2PBorrower, newVars.BP2PER),
                    expectedBorrowBalanceInUnderlying,
                    (expectedBorrowBalanceInUnderlying * 2) / 100,
                    "not expected underlying balance"
                );
                testEquality(onPoolBorrower, 0, "on pool borrower");
            }
        }

        // Borrow delta reduction with borrowers repaying
        for (uint256 i = 1; i <= 10; i++) {
            borrowers[i].approve(dai, borrowedAmount);
            borrowers[i].repay(aDai, borrowedAmount);
        }

        (, uint256 borrowP2PDeltaAfter, , ) = morpho.deltas(aDai);
        testEquality(borrowP2PDeltaAfter, 0);

        (uint256 inP2PSupplier2, uint256 onPoolSupplier2) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier2)
        );

        testEquality(inP2PSupplier2, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier2, 0);
    }

    function testDeltaWithdrawAll() public {
        // Allows only 10 unmatch borrowers
        _setDefaultMaxGasForMatching(3e6, 3e6, 2.6e6, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount + 7;

        // supplier1 and 20 borrowers are matched for suppliedAmount
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        createSigners(20);

        // 2 * NMAX borrowers borrow borrowedAmount
        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, borrowedAmount, type(uint64).max);
        }

        // Supplier withdraws max
        // Should create a delta on borrowers side
        supplier1.withdraw(aDai, type(uint256).max);

        hevm.warp(block.timestamp + (365 days));

        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(dai, type(uint64).max);
            borrowers[i].repay(aDai, type(uint64).max);
            borrowers[i].withdraw(aUsdc, type(uint64).max);
        }
    }

    function testShouldNotWithdrawWhenUnderCollaterized() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = toSupply / 2;

        // supplier1 deposits collateral
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        // supplier2 deposits collateral
        supplier2.approve(dai, toSupply);
        supplier2.supply(aDai, toSupply);

        // supplier1 tries to withdraw more than allowed
        supplier1.borrow(aUsdc, to6Decimals(toBorrow));
        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedWithdraw()"));
        supplier1.withdraw(aDai, toSupply);
    }

    // Test attack
    // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    function testWithdrawWhileAttackerSendsAToken() public {
        Attacker attacker = new Attacker(pool);
        deal(dai, address(attacker), type(uint256).max / 2);

        uint256 toSupply = 100 ether;
        uint256 collateral = 2 * toSupply;
        uint256 toBorrow = toSupply;

        // attacker sends aToken to Morpho contract
        attacker.approve(dai, address(pool), toSupply);
        attacker.deposit(dai, toSupply, address(attacker), 0);
        attacker.transfer(dai, address(morpho), toSupply);

        // supplier1 deposits collateral
        supplier1.approve(dai, toSupply);
        supplier1.supply(aDai, toSupply);

        // borrower1 deposits collateral
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));

        // supplier1 tries to withdraw
        borrower1.borrow(aDai, toBorrow);
        supplier1.withdraw(aDai, toSupply);
    }

    function testFailWithdrawZero() public {
        morpho.withdraw(aDai, 0);
    }

    function testFailInfiniteWithdraw() public {
        uint256 balanceAtTheBeginning = ERC20(dai).balanceOf(address(supplier1));

        uint256 amount = 1 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);
        supplier2.approve(dai, 9 * amount);
        supplier2.supply(aDai, 9 * amount);
        borrower1.approve(wEth, 10 * amount);
        borrower1.supply(aWeth, 10 * amount);
        borrower1.borrow(aDai, 10 * amount);

        morpho.setIsWithdrawPaused(aDai, true);

        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);
        supplier1.withdraw(aDai, amount);

        assertTrue(ERC20(dai).balanceOf(address(supplier1)) > balanceAtTheBeginning);
    }

    function testShouldWithdrawToReceiver() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(aDai, 2 * amount);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier2));

        uint256 withdrawn = supplier1.withdraw(aDai, address(supplier2), amount);

        assertEq(ERC20(dai).balanceOf(address(supplier2)), balanceBefore + amount);
        assertEq(withdrawn, amount);
    }
}
