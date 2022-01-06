// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";
import "./TestSetup.sol";

import "@config/Config.sol";
import "./HEVM.sol";
import "./Utils.sol";
import "./SimplePriceOracle.sol";
import "./User.sol";
import "./Attacker.sol";

contract SupplyTest is TestSetup {
    // 1.1 - The user supplies less than the threshold of this market, the transaction reverts.
    function testFail_Supply_1_1() public {
        supplier1.approve(dai, positionsManager.threshold(aDai) - 1);
        supplier1.supply(aDai, positionsManager.threshold(aDai) - 1);
    }

    // 1.2 - There are no available borrowers: all of the supplied amount is supplied to the pool and set `onPool`.
    function testSupply_1_2() public {
        uint256 amount = 10 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        marketsManager.updateRates(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = underlyingToScaledBalance(amount, normalizedIncome);

        assertEq(
            IERC20(aDai).balanceOf(address(positionsManager)),
            amount,
            "PositionsManager aDai balance"
        );
        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        assertLe(get_abs_diff(onPool, expectedOnPool), 1, "Supplier1 dai on pool");
        assertEq(inP2P, 0, "Supplier1 dai in P2P");
    }

    // Should be able to supply more ERC20 after already having supply ERC20
    function testSupplyMultiple() public {
        uint256 amount = 5 ether;

        supplier1.approve(dai, 2 * amount);

        supplier1.supply(aDai, amount);
        supplier1.supply(aDai, amount);

        marketsManager.updateRates(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(aDai);
        uint256 expectedOnPool = underlyingToScaledBalance(2 * amount, normalizedIncome);

        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(onPool, expectedOnPool, "Supplier1 on pool");
    }

    // 1.3 - There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.
    function testSupply_1_3() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 daiBalanceBefore = supplier1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - amount;

        supplier1.approve(dai, address(positionsManager), amount);
        supplier1.supply(aDai, amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(dai);
        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        marketsManager.updateRates(aDai);
        uint256 p2pUnitExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(amount, p2pUnitExchangeRate);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(onPoolSupplier, 0);
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P);

        assertEq(onPoolBorrower, 0);
        assertEq(inP2PBorrower, inP2PSupplier);
    }

    // 1.4 - There is 1 available borrower, he doesn't match 100% of the supplier liquidity.
    // Supplier's balance `inP2P` is equal to the borrower previous amount `onPool`, the rest is set `onPool`.
    function testSupply_1_4() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(aDai, 2 * amount);

        marketsManager.updateRates(aDai);
        uint256 p2pUnitExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(amount, p2pUnitExchangeRate);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(amount, normalizedIncome);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        assertLe(get_abs_diff(onPoolSupplier, expectedSupplyBalanceOnPool), 1, "Supplier1 on pool");
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P, "Supplier1 in P2P");

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        assertEq(onPoolBorrower, 0, "Borrower1 on pool");
        assertEq(inP2PBorrower, inP2PSupplier, "Borrower1 in P2P");
    }

    // 1.5 - There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.
    function testSupply_1_5() public {
        uint256 amount = 10 ether;

        marketsManager.setMaxNumberOfUsersInTree(3);

        uint256 totalBorrowed = 0;
        uint256 collateral = 2 * amount;

        //uint256 NMAX = positionsManager.NMAX();
        // needs to be changed to nmax
        for (uint256 i = 0; i < borrowers.length; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));

            borrowers[i].borrow(aDai, amount);
            totalBorrowed += amount;
        }

        supplier1.approve(dai, totalBorrowed);
        supplier1.supply(aDai, totalBorrowed);

        uint256 inP2P;
        uint256 onPool;
        uint256 totalInP2P = 0;

        marketsManager.updateRates(aDai);
        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);

        for (uint256 i = 0; i < borrowers.length; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));

            uint256 expectedInP2P = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertEq(expectedInP2P, amount);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(inP2P, totalInP2P);
        assertEq(onPool, 0);
    }

    // 1.6 - The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`.
    // ⚠️ most gas expensive supply scenario.
    function testSupply_1_6() public {
        uint256 amount = 10 ether;

        marketsManager.setMaxNumberOfUsersInTree(3);
        uint256 NMAX = positionsManager.NMAX();

        uint256 collateral = 2 * amount;

        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));

            borrowers[i].borrow(aDai, amount);
        }
        uint256 totalBorrowed = amount * borrowers.length;

        supplier1.approve(dai, 2 * totalBorrowed);
        supplier1.supply(aDai, 2 * totalBorrowed);

        uint256 inP2P;
        uint256 onPool;
        uint256 totalInP2P = 0;

        marketsManager.updateRates(aDai);
        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));

            uint256 expectedInP2P2 = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertEq(expectedInP2P2, amount);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        uint256 expectedOnPool = underlyingToAdUnit(totalBorrowed / 2, normalizedIncome);

        assertEq(inP2P, totalInP2P, "Supplier1 in P2P");
        assertEq(2 * onPool, expectedOnPool, "Supplier1 on pool");
    }
}
