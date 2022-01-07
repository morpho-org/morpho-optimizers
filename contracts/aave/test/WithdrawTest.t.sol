// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./TestSetup.sol";

contract WithdrawTest is TestSetup {
    // 3.1 - The user withdrawal leads to an under-collateralized position, the withdrawal reverts.
    function testFail_withdraw_3_1() public {
        uint256 amount = 100 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));

        uint256 borrowAmount = get_max_to_borrow(
            get_supply_on_pool_in_underlying(borrower1, aUsdc, usdc),
            usdc,
            dai,
            SimplePriceOracle(lendingPoolAddressesProvider.getPriceOracle())
        );
        borrower1.borrow(aDai, borrowAmount);

        borrower1.withdraw(aUsdc, to6Decimals(10 ether));
    }

    // 3.2 - The supplier withdraws less than his onPool balance. The liquidity is taken from his onPool balance.
    function test_withdraw_3_2() public {
        uint256 amount = 100 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(aUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );

        uint256 expectedOnPool = to6Decimals(
            underlyingToScaledBalance(2 * amount, lendingPool.getReserveNormalizedIncome(usdc))
        );

        assertEq(inP2P, 0);
        assertLe(get_abs_diff(onPool, expectedOnPool), 2);

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(supplier1));

        assertEq(inP2P, 0);
        assertEq(onPool, expectedOnPool / 2);
    }

    // 3.3 - The supplier withdraws more than his onPool balance

    // 3.3.1 - There is a supplier onPool available to replace him inP2P.
    // First, his liquidity onPool is taken, his matched is replaced by the available supplier up to his withdrawal amount.
    function test_withdraw_3_3_1() public {
        uint256 amount = 100 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, to6Decimals(amount / 2));

        supplier2.approve(usdc, to6Decimals(amount));
        supplier2.supply(aUsdc, to6Decimals(amount));

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );
        assertEq(inP2P, 0, "Supplier1 in p2P");
        assertEq(onPool, 0, "Supplier1 on pool");

        uint256 expected = underlyingToScaledBalance(
            amount / 2,
            lendingPool.getReserveNormalizedIncome(usdc)
        );
        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(supplier2));
        assertEq(inP2P, expected, "Supplier2 in p2P");
        assertEq(onPool, expected, "Supplier2 on pool");

        expected = underlyingToP2PUnit(amount / 2, marketsManager.p2pExchangeRate(aUsdc));
        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aUsdc, address(borrower1));
        assertEq(inP2P, expected, "Borrower1 in p2P");
        assertEq(onPool, 0, "Borrower1 on pool");
    }

    // 3.3.2 - There are NMAX (or less) suppliers onPool available to replace him inP2P, they supply enough to cover for the withdrawn liquidity.
    // First, his liquidity onPool is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
    function test_withdraw_3_3_2() public {
        uint256 amount = 200 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(aDai, 2 * amount);
        borrower1.borrow(aUsdc, to6Decimals(amount));

        setNMAXAndCreateSigners(10);
        uint256 nmax = positionsManager.NMAX();
        uint256 supplyAmount = amount / (nmax - 1);
        for (uint256 i = 1; i < nmax; i++) {
            suppliers[i].approve(usdc, to6Decimals(supplyAmount));
            suppliers[i].supply(aUsdc, to6Decimals(supplyAmount));
        }

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );
        assertEq(inP2P, 0, "Supplier1 in p2P");
        assertEq(onPool, 0, "Supplier1 on pool");

        uint256 expected = to6Decimals(
            underlyingToP2PUnit(amount, marketsManager.p2pExchangeRate(aUsdc))
        );
        for (uint256 i = 1; i < nmax; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(suppliers[i]));
            assertEq(inP2P, expected, "SupplierX in P2P");
            assertEq(onPool, 0, "SupplierX on pool");
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aUsdc, address(borrower1));
        assertEq(inP2P, expected, "Borrower1 in p2P");
        assertEq(onPool, 0, "Borrower1 on pool");
    }

    // 3.3.3 - There are no suppliers onPool to replace him inP2P. After withdrawing the amount onPool,
    // his P2P match(es) will be unmatched and the corresponding borrower(s) will be placed on pool.
    function test_withdraw_3_3_3() public {
        uint256 amount = 100 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, to6Decimals(amount / 2));

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );
        assertEq(inP2P, 0, "Supplier1 in p2P");
        assertEq(onPool, 0, "Supplier1 on pool");

        uint256 expected = underlyingToScaledBalance(
            amount / 2,
            lendingPool.getReserveNormalizedIncome(usdc)
        );
        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aUsdc, address(borrower1));
        assertEq(inP2P, 0, "Borrower1 in p2P");
        assertEq(onPool, expected, "Borrower1 on pool");
    }

    // 3.3.4 - There are NMAX (or less) suppliers onPool available to replace him inP2P, they don't supply enough to cover the withdrawn liquidity.
    // First, the onPool liquidity is withdrawn, then we proceed to NMAX (or less) matches. Finally, some borrowers are unmatched for an amount equal to the remaining to withdraw.
    // ⚠️ most gas expensive withdraw scenario.
    function test_withdraw_3_3_4() public {
        uint256 amount = 200 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(aUsdc, to6Decimals(amount));

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(aDai, 2 * amount);
        borrower1.borrow(aUsdc, to6Decimals(amount));

        setNMAXAndCreateSigners(10);
        uint256 nmax = positionsManager.NMAX();
        uint256 supplyAmount = amount / 2 / (nmax - 1);
        for (uint256 i = 1; i < nmax; i++) {
            suppliers[i].approve(usdc, to6Decimals(supplyAmount));
            suppliers[i].supply(aUsdc, to6Decimals(supplyAmount));
        }

        supplier1.withdraw(aUsdc, to6Decimals(amount));

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );
        assertEq(inP2P, 0, "Supplier1 in p2P");
        assertEq(onPool, 0, "Supplier1 on pool");

        uint256 expected = to6Decimals(
            underlyingToP2PUnit(amount, marketsManager.p2pExchangeRate(aUsdc))
        );
        for (uint256 i = 1; i < nmax; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(suppliers[i]));
            assertEq(inP2P, expected, "SupplierX in P2P");
            assertEq(onPool, 0, "SupplierX on pool");
        }

        expected = underlyingToAdUnit(amount, lendingPool.getReserveNormalizedVariableDebt(aUsdc));
        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aUsdc, address(borrower1));
        assertEq(inP2P, 0, "Borrower1 in p2P");
        assertEq(onPool, expected, "Borrower1 on pool");
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

    function get_supply_on_pool_in_underlying(
        User _user,
        address _aToken,
        address _token
    ) internal view returns (uint256) {
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(_aToken, address(_user));
        uint256 inUnderlying = scaledBalanceToUnderlying(
            onPool,
            lendingPool.getReserveNormalizedIncome(_token)
        );

        return inUnderlying;
    }
}
