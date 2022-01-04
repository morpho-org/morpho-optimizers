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
    function test_Supply_1_2(uint16 _amount) public {
        if (_amount <= positionsManager.threshold(aDai)) return;

        supplier1.approve(dai, address(positionsManager), _amount);
        supplier1.supply(aDai, _amount);

        marketsManager.updateRates(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = underlyingToScaledBalance(_amount, normalizedIncome);

        assertEq(IERC20(aDai).balanceOf(address(positionsManager)), _amount);
        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(positionsManager)
        );
        assertEq(onPool, expectedOnPool);
        assertEq(inP2P, 0);
    }

    // Should be able to supply more ERC20 after already having supply ERC20
    function test_multiple_supply() public {
        uint256 amount = 10 ether;

        supplier1.approve(dai, address(positionsManager), 2 * amount);

        supplier1.supply(aDai, amount);
        supplier1.supply(aDai, amount);

        marketsManager.updateRates(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(aDai);
        uint256 expectedOnPool = underlyingToScaledBalance(2 * amount, normalizedIncome);

        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(onPool, expectedOnPool);
    }

    // 1.3 - There is 1 available borrower, he matches 100% of the supplier liquidity, everything is `inP2P`.
    function test_Supply_1_3(uint16 _amount) public {
        if (_amount <= positionsManager.threshold(aDai)) return;
        borrower1.approve(usdc, address(positionsManager), to6Decimals(2 * _amount));
        borrower1.supply(aUsdc, to6Decimals(2 * _amount));
        borrower1.borrow(aDai, _amount);

        uint256 daiBalanceBefore = supplier1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - _amount;

        supplier1.approve(dai, address(positionsManager), _amount);
        supplier1.supply(aDai, _amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(dai);
        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        marketsManager.updateRates(aDai);
        uint256 p2pUnitExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(_amount, p2pUnitExchangeRate);

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.supplyBalanceInOf(
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
    function test_Supply_1_4(uint16 _amount) public {
        if (_amount <= positionsManager.threshold(aDai)) return;
        borrower1.approve(usdc, address(positionsManager), to6Decimals(10 * _amount));
        borrower1.supply(aUsdc, to6Decimals(10 * _amount));
        borrower1.borrow(aDai, _amount / 2);

        uint256 daiBalanceBefore = supplier1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - _amount;

        supplier1.approve(dai, address(positionsManager), _amount);
        supplier1.supply(aDai, _amount);

        uint256 daiBalanceAfter = supplier1.balanceOf(dai);
        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        marketsManager.updateRates(aDai);
        uint256 p2pUnitExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedSupplyBalanceInP2P = underlyingToP2PUnit(_amount / 2, p2pUnitExchangeRate);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(
            _amount / 2,
            normalizedIncome
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(onPoolSupplier, expectedSupplyBalanceOnPool);
        assertEq(inP2PSupplier, expectedSupplyBalanceInP2P);

        assertEq(onPoolBorrower, 0);
        assertEq(inP2PBorrower, inP2PSupplier);
    }

    // 1.5 - There are NMAX (or less) borrowers that match the supplied amount, everything is `inP2P` after NMAX (or less) match.
    function test_Supply_1_5(uint256 _amount) public {
        if (_amount <= positionsManager.threshold(aDai)) return;
        if (type(uint256).max / 2 < _amount) return; // to avoid overflow on the collateral

        //uint256 NMAX = positionsManager.NMAX();

        uint256 totalBorrowed = 0;
        uint256 collateral = 2 * _amount;

        // needs to be changed to nmax
        for (uint256 i = 0; i < borrowers.length; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));

            borrowers[i].borrow(aDai, _amount);
            totalBorrowed += _amount;
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

            assertEq(expectedInP2P, _amount);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(inP2P, totalInP2P);
        assertEq(onPool, 0);
    }

    // 1.6 - The NMAX biggest borrowers don't match all of the supplied amount, after NMAX match, the rest is supplied and set `onPool`.
    // ⚠️ most gas expensive supply scenario.
    function test_Supply_1_6(uint256 _amount) public {
        if (_amount <= positionsManager.threshold(aDai)) return;
        if (type(uint256).max / 2 < _amount) return; // to avoid overflow on the collateral

        //uint256 NMAX = positionsManager.NMAX();

        uint256 totalBorrowed = 0;
        uint256 collateral = 2 * _amount;

        // NMAX
        for (uint256 i = 0; i < borrowers.length; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));

            borrowers[i].borrow(aDai, _amount);
            totalBorrowed += _amount;
        }

        supplier1.approve(dai, 2 * totalBorrowed);
        supplier1.supply(aDai, 2 * totalBorrowed);

        uint256 inP2P;
        uint256 onPool;
        uint256 totalInP2P = 0;

        marketsManager.updateRates(aDai);
        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);

        for (uint256 i = 0; i < borrowers.length; i++) {
            (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));

            uint256 expectedInP2P2 = p2pUnitToUnderlying(inP2P, p2pExchangeRate);

            assertEq(expectedInP2P2, _amount);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        uint256 expectedOnPool = underlyingToScaledBalance(totalBorrowed / 2, normalizedIncome);

        assertEq(inP2P, totalInP2P);
        assertEq(onPool, expectedOnPool);
    }
}
