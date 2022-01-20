// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/libraries/aave/WadRayMath.sol";

import "./utils/TestSetup.sol";

contract TestNmax is TestSetup {
    function test_supply_NMAX() public {
        uint16 NMAX = 101;
        setNMAXAndCreateSigners(NMAX);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint256 amountPerBorrower = amount / (2 * NMAX);
        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }
        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);
    }

    function test_borrow_NMAX() public {
        uint16 NMAX = 101;
        setNMAXAndCreateSigners(NMAX);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;
        uint256 amountPerSupplier = amount / (2 * NMAX);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);
    }

    function test_withdraw_NMAX() public {
        uint16 NMAX = 101;
        setNMAXAndCreateSigners(NMAX);

        uint256 borrowedAmount = 100000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (NMAX - 1));
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
        }
        supplier1.withdraw(aDai, suppliedAmount);
    }

    function test_repay_NMAX() public {
        uint16 NMAX = 101;
        setNMAXAndCreateSigners(NMAX);

        uint256 suppliedAmount = 10000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (2 * (NMAX - 1));
        // minus because borrower1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        // Borrower1 repays all of his debt
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(aDai, borrowedAmount);
    }

    function test_liquidate_NMAX() public {
        uint16 NMAX = 101;
        setNMAXAndCreateSigners(NMAX);

        uint256 collateral = 100000 ether;
        uint256 borrowedAmount = (collateral * 80) / 100;
        uint256 suppliedAmount = borrowedAmount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        uint256 amountPerSupplier = (suppliedAmount) / (2 * (NMAX - 1));
        uint256 amountPerBorrower = (borrowedAmount) / (2 * (NMAX - 1));
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        // Change Oraclefalse
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getAssetPrice(usdc) * 90) / 100);

        // Liquidate
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), borrowedAmount / 2);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), borrowedAmount / 2);
    }

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        hevm.store(
            address(lendingPoolAddressesProvider),
            keccak256(abi.encode(bytes32("PRICE_ORACLE"), 2)),
            bytes32(uint256(uint160(address(customOracle))))
        );

        for (uint256 i = 0; i < pools.length; i++) {
            address underlying = IAToken(pools[i]).UNDERLYING_ASSET_ADDRESS();

            customOracle.setDirectPrice(underlying, oracle.getAssetPrice(underlying));
        }

        return customOracle;
    }
}
