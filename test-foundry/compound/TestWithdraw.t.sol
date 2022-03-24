// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/compound/interfaces/IPositionsManagerForCompound.sol";

import "./setup/TestSetup.sol";
import {Attacker} from "../common/helpers/Attacker.sol";

contract TestWithdraw is TestSetup {
    function testWithdraw1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        borrower1.borrow(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueAboveMax()"));
        borrower1.withdraw(cUsdc, to6Decimals(collateral));
    }

    function testWithdraw2() public {
        uint256 amount = 10000 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(cUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(supplier1)
        );

        uint256 expectedOnPool = to6Decimals(
            underlyingToPoolSupplyBalance(2 * amount, ICToken(cUsdc).exchangeRateCurrent())
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(cUsdc, to6Decimals(amount));

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool / 2);
    }

    function testWithdrawAll() public {
        uint256 amount = 10000 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(cUsdc, to6Decimals(amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(supplier1)
        );

        uint256 balanceBefore = supplier1.balanceOf(usdc);

        uint256 expectedOnPool = to6Decimals(
            underlyingToPoolSupplyBalance(amount, ICToken(cUsdc).exchangeRateCurrent())
        );

        testEquality(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(cUsdc, type(uint256).max);

        uint256 balanceAfter = supplier1.balanceOf(usdc);
        (inP2P, onPool) = positionsManager.supplyBalanceInOf(cUsdc, address(supplier1));

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
        testEquality(
            balanceAfter - balanceBefore,
            getBalanceOnCompound(to6Decimals(amount), ICToken(cUsdc).exchangeRateStored())
        );
    }

    // 3.3 - The supplier withdraws more than his onPool balance

    // 3.3.1 - There is a supplier onPool available to replace him inP2P.
    // First, his liquidity onPool is taken, his matched is replaced by the available supplier up to his withdrawal amount.
    function testWithdraw3_1() public {
        uint256 borrowedAmount = 10000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToPoolSupplyBalance(
            suppliedAmount / 2,
            ICToken(cDai).exchangeRateCurrent()
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(cDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(cDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier2)
        );
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
        uint256 expectedInP2P = underlyingToP2PUnit(suppliedAmount / 2, supplyP2PExchangeRate);
        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(inP2PSupplier, expectedInP2P);

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PSupplier, inP2PBorrower1);
    }

    function test_withdraw_3_3_2() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 borrowedAmount = 100000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = underlyingToPoolSupplyBalance(
            suppliedAmount / 2,
            ICToken(cDai).exchangeRateCurrent()
        );

        testEquality(onPoolSupplier, expectedOnPool);
        testEquality(onPoolBorrower, 0);
        testEquality(inP2PSupplier, inP2PBorrower);

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint8 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (NMAX - 1);
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        // supplier1 withdraws suppliedAmount
        supplier1.withdraw(cDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );
        testEquality(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
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

            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));
            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, supplyP2PExchangeRate);

            testEquality(expectedInP2P, amountPerSupplier);
            testEquality(onPool, 0);
        }
    }

    // TODO
    function testWithdraw3_3() public {}

    // TODO
    function testWithdraw3_4() public {}

    struct Vars {
        uint256 LR;
        uint256 SPY;
        uint256 VBR;
        uint256 NVD;
        uint256 BP2PD;
        uint256 BP2PA;
        uint256 BP2PER;
    }

    // TODO
    function testDeltaWithdraw() public {}

    // TODO
    function testShouldNotWithdrawWhenUnderCollaterized() public {}

    // TODO
    // Test attack
    // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    function testWithdrawWhileAttackerSendsAToken() public {}

    function testFailWithdrawZero() public {
        positionsManager.withdraw(cDai, 0);
    }
}
