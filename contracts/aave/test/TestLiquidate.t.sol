// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract LiquidateTest is TestSetup {
    // 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function testFail_liquidate_5_1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);
    }

    // 5.2 - A user liquidate a borrower that has not enough collateral to cover for his debt.
    function test_liquidate_5_2() public {
        uint256 collateral = 100000 ether;
        uint256 amount = (collateral * 80) / 100;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getAssetPrice(usdc) * 90) / 100);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );
        testEquality(expectedBorrowBalanceOnPool, amount / 2);
        testEquality(inP2PBorrower, 0);

        // Check borrower1 supply balance
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(borrower1)
        );
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 expectedOnPool = underlyingToAdUnit(amount / 2, normalizedIncome);
        testEquality(onPoolBorrower, expectedOnPool);
        testEquality(inP2PBorrower, 0);
    }

    // 5.3 - The liquidation is made of a Repay and Withdraw performed on a borrower's position on behalf of a liquidator.
    //       At most, the liquidator can liquidate 50% of the debt of a borrower and take the corresponding collateral (plus a bonus).
    //       Edge-cases here are at most the combination from part 3. and 4. called with the previous amount.
    function test_liquidate_5_3() public {
        uint256 collateral = 100000 ether;
        uint256 borrowedAmount = (collateral * 80) / 100;
        uint256 suppliedAmount = borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // NMAX borrowers have debt waiting on pool
        uint16 NMAX = 20;
        setNMAXAndCreateSigners(NMAX);

        uint256 amountPerSupplier = (suppliedAmount) / (2 * (NMAX - 1));
        uint256 amountPerBorrower = (borrowedAmount) / (2 * (NMAX - 1));
        // minus 1 because supplier1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(aDai, amountPerSupplier);

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getAssetPrice(usdc) * 90) / 100);

        // Liquidate
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), borrowedAmount / 2);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), borrowedAmount / 2);

        // Check borrower1 balance
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 p2pExchangeRate = marketsManager.p2pExchangeRate(aDai);
        uint256 expectedBorrowBalanceInP2P = p2pUnitToUnderlying(inP2PBorrower, p2pExchangeRate);
        uint256 expectedBorrowBalanceOnPool = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        testEquality(expectedBorrowBalanceOnPool + expectedBorrowBalanceInP2P, borrowedAmount / 2);
    }

    // ----------

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        hevm.store(
            address(lendingPoolAddressesProvider),
            keccak256(abi.encode(bytes32("PRICE_ORACLE"), 2)),
            bytes32(uint256(uint160(address(customOracle))))
        );

        // !!! WARNING !!! All tokens added with createMarket must be set
        customOracle.setDirectPrice(dai, oracle.getAssetPrice(dai));
        customOracle.setDirectPrice(usdc, oracle.getAssetPrice(usdc));
        customOracle.setDirectPrice(usdt, oracle.getAssetPrice(usdt));
        customOracle.setDirectPrice(wbtc, oracle.getAssetPrice(wbtc));
        customOracle.setDirectPrice(wmatic, oracle.getAssetPrice(wmatic));

        return customOracle;
    }
}
