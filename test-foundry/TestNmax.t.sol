// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/libraries/aave/WadRayMath.sol";

import "./utils/TestSetup.sol";

contract TestNmax is TestSetup {
    // Define the value of NMAX for the estimations
    uint16 public NMAX = 20;

    // 1: Dai market P2P is full of matches.
    // 2: There are NMAX borrowers waiting on Pool.
    // 3: Alices comes and is matched to NMAX borrowers. The excess has to be supplied on pool.
    function test_supply_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(2 * NMAX);

        uint256 aliceAmount = (NMAX + 10) * 1e18;

        // 1: create NMAX big matches on DAI market
        uint256 matchedAmount = (1000 * NMAX * 1e18);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: There are NMAX borrowers waiting on Pool.
        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(2 * 1e18));
            borrowers[i].supply(aUsdc, to6Decimals(2 * 1e18));
            borrowers[i].borrow(aDai, 1e18);
        }

        // 3: Alices comes and is matched to NMAX borrowers. The excess has to be supplied on pool.
        Alice.approve(dai, aliceAmount);
        Alice.supply(aDai, aliceAmount);
    }

    // 1: Dai market P2P is full of matches.
    // 2: There are NMAX suppliers waiting on Pool.
    // 3: Alices comes and is matched to NMAX suppliers. The excess has to be borrowed on pool.
    function test_borrow_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(2 * NMAX);

        uint256 aliceAmount = (NMAX + 10) * 1e18;

        // 1: create NMAX big matches on DAI market
        uint256 matchedAmount = (1000 * NMAX * 1e18);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: There are NMAX suppliers waiting on Pool.
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, 1e18);
            suppliers[i].supply(aDai, 1e18);
        }

        // 3: Alices comes and is matched to NMAX borrowers. The excess has to be supplied on pool.
        Alice.approve(usdc, 2 * aliceAmount);
        Alice.supply(aUsdc, 2 * aliceAmount);
        Alice.borrow(aDai, aliceAmount);
    }

    // 1: DAI P2P is full of big matches.
    // 2: Alice supplies DAI, then 2*NMAX borrowers come and match her liquidity.
    // 3: There are NMAX dai supplier on pool.
    // 4: Alice withdraws everything.
    // 5: NMAX match suppliers.
    // 6: NMAX unmatch borrower.
    function test_withdraw_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(3 * NMAX);

        // 1: create NMAX big matches on DAI market
        uint256 matchedAmount = (1000 * NMAX * 1e18);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: Alice comes to supply DAI & is matched with 2 NMAX borrowers
        uint256 aliceAmount = 2 * NMAX * 1e18;
        Alice.approve(dai, aliceAmount);
        Alice.supply(aDai, aliceAmount);

        for (uint256 i = NMAX; i < 3 * NMAX; i++) {
            borrowers[i].approve(usdc, to6Decimals(2 * 1e18));
            borrowers[i].supply(aUsdc, to6Decimals(2 * 1e18));

            borrowers[i].borrow(aDai, 1e18);
        }

        // 3: There are NMAX Dai suppliers on Pool
        for (uint256 i = NMAX; i < 2 * NMAX; i++) {
            suppliers[i].approve(dai, 1e18);
            suppliers[i].supply(aDai, 1e18);
        }

        // 4: Alice withdraws everything
        Alice.withdraw(aDai, aliceAmount);
    }

    // 1: DAI P2P is full of big matches.
    // 2: Alice borrows DAI, then 2*NMAX suppliers come and match her liquidity.
    // 3: There are NMAX dai borrowers on pool.
    // 4: Alice repays everything.
    // 5: NMAX match borrower.
    // 6: NMAX unmatch supplier.
    function test_repay_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(3 * NMAX);

        // 1: create NMAX big matches on DAI market
        uint256 matchedAmount = (1000 * NMAX * 1e18);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].approve(dai, matchedAmount);
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].approve(usdc, to6Decimals(2 * matchedAmount));
            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: Alice borrows DAI & is matched with 2*NMAX suppliers
        uint256 aliceAmount = 2 * NMAX * 1e18;
        Alice.approve(usdc, 2 * aliceAmount);
        Alice.supply(aUsdc, 2 * aliceAmount);
        Alice.borrow(aDai, aliceAmount);

        for (uint256 i = NMAX; i < 3 * NMAX; i++) {
            suppliers[i].approve(dai, 1e18);
            suppliers[i].supply(aDai, 1e18);
        }

        // 3: There are NMAX Dai borrowers on Pool
        for (uint256 i = NMAX; i < 2 * NMAX; i++) {
            suppliers[i].approve(usdc, to6Decimals(2 * 1e18));
            suppliers[i].supply(aUsdc, to6Decimals(2 * 1e18));

            suppliers[i].borrow(dai, 1e18);
        }

        // 4: Alice repays everything
        Alice.approve(dai, aliceAmount);
        Alice.repay(aDai, aliceAmount);
    }

    function test_liquidate_NMAX() public {
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
