// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/libraries/aave/WadRayMath.sol";

import "./utils/TestSetup.sol";

contract TestNmax is TestSetup {
    // Define the value of NMAX for the estimations
    uint8 public NMAX = 20;

    // 1: DAI P2P is full of big matches so that the insert sorted also loops NMAX times.
    // 2: There are NMAX borrowers waiting on Pool.
    // 3: Alices comes and is matched to NMAX borrowers. The excess has to be supplied on pool.
    function test_supply_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager, rewardsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(2 * NMAX);

        // Need to change NMAX to uint256 otherwise this calculation overflows.
        uint256 NMAX_256 = NMAX;
        uint256 aliceAmount = (NMAX_256 + 10) * 1e18;
        // Amount breakdown:
        // 2: because we need to match 2 times Nmax users
        // +10*1e18: to have additional unmatched liquidity going to the pool.

        // 1: create NMAX big matches on DAI market
        uint256 matchedAmount = (1000 * NMAX_256 * 1e18);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: There are NMAX borrowers waiting on Pool.
        for (uint256 i = 0; i < NMAX; i++) {
            borrowers[i].supply(aUsdc, to6Decimals(2 * 1e18));
            borrowers[i].borrow(aDai, 1e18);
        }

        // 3: Alices comes and is matched to NMAX borrowers. The excess has to be supplied on pool.
        Alice.supply(aDai, aliceAmount);
    }

    // 1: DAI P2P is full of big matches so that the insert sorted also loops NMAX times.
    // 2: There are NMAX suppliers waiting on Pool.
    // 3: Alices comes and is matched to NMAX suppliers. The excess has to be borrowed on pool.
    function test_borrow_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager, rewardsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(2 * NMAX);

        // Need to change NMAX to uint256 otherwise this calculation overflows.
        uint256 NMAX_256 = NMAX;
        uint256 aliceAmount = (NMAX_256 + 10) * 1e18;
        // Amount breakdown:
        // 2: because we need to match 2 times Nmax users
        // +10*1e18: to have additional unmatched liquidity going to the pool.

        // 1: create NMAX big matches on DAI market
        uint256 matchedAmount = (1000 * NMAX_256 * 1e18);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: There are NMAX suppliers waiting on Pool.
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, 1e18);
        }

        // 3: Alices comes and is matched to NMAX borrowers. The excess has to be supplied on pool.
        Alice.supply(aUsdc, to6Decimals(2 * aliceAmount));
        Alice.borrow(aDai, aliceAmount);
    }

    // 1: DAI P2P is full of big matches so that the insert sorted also loops NMAX times.
    // 2: Alice supplies DAI, then 2*NMAX borrowers come and match her liquidity.
    // 3: There are NMAX dai suppliers on pool.
    // 4: Alice withdraws everything.
    // 5: NMAX match suppliers.
    // 6: NMAX unmatch borrowers.
    function test_withdraw_NMAX() public {
        // 0: create Alice, set Nmax & create signers.
        User Alice = (new User(positionsManager, marketsManager, rewardsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(3 * NMAX);

        // 1: create NMAX big matches on DAI market
        // Need to change NMAX to uint256 otherwise this calculation overflows.
        uint256 NMAX_256 = NMAX;
        uint256 matchedAmount = (1000 * NMAX_256 * 1e18);
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: Alice comes to supply DAI & is matched with 2 NMAX borrowers
        uint256 aliceAmount = (NMAX_256 + 10) * 1e18 * 2;
        // Amount breakdown:
        // 2: because we need to match 2 times Nmax users
        // +10*1e18: to have additional unmatched liquidity going to the pool.
        Alice.supply(aDai, aliceAmount);

        for (uint256 i = NMAX; i < 3 * NMAX; i++) {
            borrowers[i].supply(aUsdc, to6Decimals(2 * 1e18));

            borrowers[i].borrow(aDai, 1e18);
        }

        // 3: There are NMAX Dai suppliers on Pool
        for (uint256 i = NMAX; i < 2 * NMAX; i++) {
            suppliers[i].supply(aDai, 1e18);
        }

        // 4: Alice withdraws everything
        Alice.withdraw(aDai, aliceAmount);
    }

    // 1: DAI P2P is full of big matches so that the insert sorted also loops NMAX times.
    // 2: Alice borrows DAI, then 2*NMAX suppliers come and match her liquidity.
    // 3: There are NMAX dai borrowers on pool.
    // 4: Alice repays everything.
    // 5: NMAX match borrowers.
    // 6: NMAX unmatch suppliers.
    function test_repay_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager, rewardsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(3 * NMAX);

        // 1: create NMAX big matches on DAI market
        // Need to change NMAX to uint256 otherwise this calculation overflows.
        uint256 NMAX_256 = NMAX;
        uint256 matchedAmount = (1000 * NMAX_256 * 1e18);

        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, matchedAmount);

            borrowers[i].supply(aUsdc, to6Decimals(2 * matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: Alice borrows DAI & is matched with 2*NMAX suppliers
        uint256 aliceAmount = (NMAX_256 + 10) * 1e18 * 2;
        // Amount breakdown:
        // 2: because we need to match 2 times Nmax users
        // +10*1e18: to have additional unmatched liquidity going to the pool.
        Alice.supply(aUsdc, to6Decimals(2 * aliceAmount));
        Alice.borrow(aDai, aliceAmount);

        for (uint256 i = NMAX; i < 3 * NMAX; i++) {
            suppliers[i].supply(aDai, 1e18);
        }

        // 3: There are NMAX Dai borrowers on Pool
        for (uint256 i = NMAX; i < 2 * NMAX; i++) {
            suppliers[i].supply(aUsdc, to6Decimals(2 * 1e18));

            suppliers[i].borrow(aDai, 1e18);
        }

        // 4: Alice repays everything
        Alice.repay(aDai, aliceAmount);
    }

    // 1: DAI P2P is full of big matches so that the insert sorted also loops NMAX times.
    // 2: USDC P2P is full of big matches so that the insert sorted also loops NMAX times.
    // 3: Alice supplies USDC, then 4*NMAX borrowers come and match her liquidity.
    // 4: Alice borrows DAI, then 4*NMAX suppliers come and match her liquidity.
    // 5: There are NMAX DAI borrowers on pool.
    // 6: There are NMAX USDC suppliers on pool.
    // 7: There is a price variation, Alice gets liquidated.
    // 8: 50% of her debt is repaid, 50% of her collateral is withdrawn.
    // 9: This result in NMAX match borrowers, NMAX unmatch suppliers and repaying on Pool.
    // 10: Then, for the withdraw, NMAX match suppliers, NMAX unmatch borrowers and withdrawing on Pool.
    function test_liquidate_NMAX() public {
        // 0: Create Alice, set Nmax & create signers
        User Alice = (new User(positionsManager, marketsManager, rewardsManager));
        writeBalanceOf(address(Alice), dai, type(uint256).max / 2);
        writeBalanceOf(address(Alice), usdc, type(uint256).max / 2);
        positionsManager.setNmaxForMatchingEngine(NMAX);
        createSigners(7 * NMAX);

        // Need to change NMAX to uint256 otherwise there are overflows.
        uint256 NMAX_256 = NMAX;

        uint256 individualDaiAmount = 8 ether;
        uint256 individualUsdcAmount = 10 ether;

        // Amount breakdown:
        // 4: because we need to match 4 times Nmax users
        // NMAX_256: to avoid overflow
        // individualUsdcAmount: representing 1 user's amount
        // +10*individualUsdcAmount: to have additional unmatched liquidity going to the pool.
        uint256 aliceCollateralAmount = 4 *
            NMAX_256 *
            individualUsdcAmount +
            10 *
            individualUsdcAmount;
        uint256 aliceBorrowedAmount = 4 * NMAX_256 * individualDaiAmount + 10 * individualDaiAmount;

        // 1: create NMAX big matches on DAI market
        uint256 matchedAmount = 100 * individualDaiAmount * NMAX_256 * 1e18;
        for (uint256 i = 0; i < NMAX; i++) {
            suppliers[i].supply(aDai, matchedAmount);

            writeBalanceOf(address(borrowers[i]), wbtc, type(uint256).max / 2);
            borrowers[i].supply(aWbtc, 100 * to6Decimals(matchedAmount));
            borrowers[i].borrow(aDai, matchedAmount);
        }

        // 2: create NMAX big matches on USDC market
        for (uint256 i = NMAX; i < 2 * NMAX; i++) {
            suppliers[i].supply(aUsdc, to6Decimals(matchedAmount));

            writeBalanceOf(address(borrowers[i]), wbtc, type(uint256).max / 2); // Use WBTC to avoid affecting DAI and USDC markets
            borrowers[i].supply(aWbtc, 100 * to6Decimals(matchedAmount));
            borrowers[i].borrow(aUsdc, to6Decimals(matchedAmount));
        }

        // 3: Alice supplies USDC, then 4*NMAX borrowers come and match her liquidity.
        Alice.supply(aUsdc, to6Decimals(aliceCollateralAmount));

        for (uint256 i = 2 * NMAX; i < 6 * NMAX; i++) {
            writeBalanceOf(address(borrowers[i]), wbtc, type(uint256).max / 2); // Use WBTC to avoid affecting DAI and USDC markets
            borrowers[i].supply(aWbtc, 100 * to6Decimals(individualUsdcAmount));

            borrowers[i].borrow(aUsdc, to6Decimals(individualUsdcAmount));
        }

        // 4: Alice borrows DAI & is matched with 4*NMAX suppliers
        Alice.borrow(aDai, aliceBorrowedAmount);

        for (uint256 i = 2 * NMAX; i < 6 * NMAX; i++) {
            suppliers[i].supply(aDai, individualDaiAmount);
        }

        // 5: There are NMAX DAI borrowers on pool.
        for (uint256 i = 6 * NMAX; i < 7 * NMAX; i++) {
            writeBalanceOf(address(borrowers[i]), wbtc, type(uint256).max / 2); // Use WBTC to avoid affecting DAI and USDC markets
            borrowers[i].supply(aWbtc, 100 * to6Decimals(individualDaiAmount));
            borrowers[i].borrow(aDai, individualDaiAmount);
        }

        // 6: There are NMAX USDC suppliers on pool.
        for (uint256 i = 4 * NMAX; i < 5 * NMAX; i++) {
            suppliers[i].supply(aUsdc, to6Decimals(individualUsdcAmount));
        }

        // 7: There is a price variation, Alice gets liquidated.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 11) / 10);

        (uint256 inP2PAlice, uint256 onPoolAlice) = positionsManager.borrowBalanceInOf(
            aDai,
            address(Alice)
        );

        uint256 totalBorrowedAlice = aDUnitToUnderlying(
            onPoolAlice,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        ) + p2pUnitToUnderlying(inP2PAlice, marketsManager.borrowP2PExchangeRate(aDai));

        User liquidator = borrower1;
        liquidator.liquidate(aDai, aUsdc, address(Alice), totalBorrowedAlice / 2);
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
