// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/libraries/aave/WadRayMath.sol";

import "./utils/TestSetup.sol";

contract TestNmax is TestSetup {
    function test_supply_NMAX() public {
        uint16 NMAX = 20;
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
        uint16 NMAX = 20;
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
        uint16 NMAX = 21;
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
        uint16 NMAX = 21;
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

    // First step. alice comes and borrows 'daiBorrowAmount' while putting in collateral 'usdcCollateralAmount'
    // Second step. 2*NMAX suppliers are going to be matched with her debt.
    // (2*NMAX because in the liquidation we have a max liquidation of 50%)
    // Third step. 2*NMAX borrowers comes and are match with the collateral.
    // Fourth step. There is a price variation.
    // Fifth step. 50% of Alice's position is liquidated, thus generating NMAX unmatch of suppliers and borrowers.
    function test_liquidate_NMAX() public {
        uint16 NMAX = 20;
        positionsManager.setNmaxForMatchingEngine(NMAX);

        while (borrowers.length < 2 * NMAX) {
            borrowers.push(new User(positionsManager, marketsManager));
            writeBalanceOf(address(borrowers[borrowers.length - 1]), dai, type(uint256).max / 2);
            writeBalanceOf(address(borrowers[borrowers.length - 1]), usdc, type(uint256).max / 2);

            suppliers.push(new User(positionsManager, marketsManager));
            writeBalanceOf(address(suppliers[suppliers.length - 1]), dai, type(uint256).max / 2);
            writeBalanceOf(address(suppliers[suppliers.length - 1]), usdc, type(uint256).max / 2);
        }

        uint256 collateral = 10000 ether;
        uint256 debt = (collateral * 80) / 100;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, debt);

        uint256 suppliedPerUser = (debt) / (2 * NMAX);
        uint256 borrowerPerUser = (collateral) / (2 * NMAX);

        for (uint256 i = 0; i < 2 * NMAX; i++) {
            writeBalanceOf(address(suppliers[i]), wbtc, 100 * 1e8);
            suppliers[i].approve(wbtc, 10 * 1e8); // Just to increase the healf factor
            suppliers[i].supply(aWbtc, 10 * 1e8); // without affecting matchs/unmatchs

            suppliers[i].approve(dai, suppliedPerUser);
            suppliers[i].supply(aDai, suppliedPerUser);

            suppliers[i].borrow(aUsdc, to6Decimals(borrowerPerUser));
        }

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 110) / 100);

        // Get the exact borrow balance in underlying to avoid rounding errors
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 totalBorrowed = aDUnitToUnderlying(
            onPoolBorrower,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        ) + p2pUnitToUnderlying(inP2PBorrower, marketsManager.borrowP2PExchangeRate(aDai));

        // Liquidate
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), totalBorrowed / 2);
        liquidator.liquidate(aDai, aUsdc, address(borrower1), totalBorrowed / 2);
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
