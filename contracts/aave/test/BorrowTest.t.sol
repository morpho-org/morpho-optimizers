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

contract BorrowTest is TestSetup {
    // 2.1 - The user borrows less than the threshold of the given market, the transaction reverts.
    function testFail_2_1() public {
        uint256 amount = to6Decimals(positionsManager.threshold(aDai) - 1);
        borrower1.approve(dai, amount);
        borrower1.borrow(aDai, amount);
    }

    // 2.2 - The borrower tries to borrow more than his collateral allows, the transaction reverts.
    function testFail_borrow_2_2() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, amount);
        borrower1.supply(aUsdc, amount);

        uint256 maxToBorrow = get_max_to_borrow(
            amount,
            usdc,
            dai,
            SimplePriceOracle(lendingPoolAddressesProvider.getPriceOracle())
        );
        borrower1.borrow(aDai, maxToBorrow + 1);
    }

    // 2.3 - There are no available suppliers: all of the borrowed amount is onPool.
    function test_borrow_2_3() public {
        uint256 amount = 10 ether;

        borrower1.approve(usdc, amount);
        borrower1.supply(aUsdc, amount);
        borrower1.borrow(aDai, amount / 2);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(inP2P, 0);
        assertGt(onPool, 0);
    }

    // 2.4 - There is 1 available supplier, he matches 100% of the borrower liquidity, everything is inP2P.
    function test_borrow_2_4() public {
        uint256 amount = 10 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(usdc, amount);
        borrower1.supply(aUsdc, amount);
        borrower1.borrow(aDai, amount / 2);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertGt(supplyInP2P, 0);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        assertEq(inP2P, supplyInP2P);
        assertEq(onPool, 0);
    }

    // 2.5 - There is 1 available supplier, he doesn't match 100% of the borrower liquidity.
    // Borrower inP2P is equal to the supplier previous amount onPool, the rest is set onPool.
    function test_borrow_2_5() public {
        uint256 amount = 2 ether;
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        amount = 10 ether;
        borrower1.approve(usdc, amount);
        borrower1.supply(aUsdc, amount);
        borrower1.borrow(aDai, amount / 2);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(inP2P, supplyInP2P);
        assertGt(onPool, 0);
    }

    // 2.6 - There are NMAX (or less) supplier that match the borrowed amount, everything is inP2P after NMAX (or less) match.
    function test_borrow_2_6() public {
        uint256 amount = 5 ether;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < suppliers.length; i++) {
            suppliers[i].approve(dai, amount);
            suppliers[i].supply(aDai, amount);
            totalAmount += amount;
        }

        uint256 borrowerSupplyAmount = totalAmount * 2;
        borrower1.approve(usdc, borrowerSupplyAmount);
        borrower1.supply(aUsdc, borrowerSupplyAmount);
        borrower1.borrow(aDai, totalAmount);

        uint256 inP2P;
        uint256 onPool;
        uint256 totalInP2P = 0;
        for (uint256 i = 0; i < suppliers.length; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            assertGt(inP2P, 0);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
        assertEq(inP2P, totalInP2P);
        assertEq(onPool, 0);
    }

    // 2.7 - The NMAX biggest supplier don't match all of the borrowed amount, after NMAX match, the rest is borrowed and set onPool.
    // ⚠️ most gas expensive borrow scenario.
    function test_borrow_2_7() public {
        uint256 amount = 5 ether;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < suppliers.length; i++) {
            suppliers[i].approve(dai, amount);
            suppliers[i].supply(aDai, amount);
            totalAmount += amount;
        }

        uint256 borrowerSupplyAmount = totalAmount * 4;
        borrower1.approve(usdc, borrowerSupplyAmount);
        borrower1.supply(aUsdc, borrowerSupplyAmount);
        borrower1.borrow(aDai, totalAmount * 2);

        uint256 inP2P;
        uint256 onPool;
        uint256 totalInP2P = 0;
        for (uint256 i = 0; i < suppliers.length; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
            assertGt(inP2P, 0);
            assertEq(onPool, 0);

            totalInP2P += inP2P;
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
        assertEq(inP2P, totalInP2P);
        assertGt(onPool, 0);
    }

    // ----------

    function get_max_to_borrow(
        uint256 _collateralInUnderlying,
        address _suppliedAsset,
        address _borrowedAsset,
        SimplePriceOracle _oracle
    ) internal view returns (uint256) {
        (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
            .getReserveConfigurationData(_borrowedAsset);
        uint256 maxToBorrow = (((((_collateralInUnderlying *
            _oracle.getAssetPrice(_suppliedAsset)) / 10**ERC20(_suppliedAsset).decimals()) *
            10**ERC20(_borrowedAsset).decimals()) / _oracle.getAssetPrice(_borrowedAsset)) *
            liquidationThreshold) / PERCENT_BASE;
        return maxToBorrow;
    }
}
