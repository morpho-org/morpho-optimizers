// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";

import "@config/Config.sol";
import "./HEVM.sol";
import "./Utils.sol";
import "./SimplePriceOracle.sol";
import "./User.sol";
import "./Attacker.sol";

contract TestSetup is DSTest, Config, Utils {
    HEVM hevm = HEVM(HEVM_ADDRESS);

    PositionsManagerForAave internal positionsManager;
    PositionsManagerForAave internal fakePositionsManager;
    MarketsManagerForAave internal marketsManager;

    ILendingPoolAddressesProvider lendingPoolAddressesProvider;
    ILendingPool lendingPool;
    IProtocolDataProvider protocolDataProvider;
    IPriceOracleGetter oracle;

    User supplier1;
    User supplier2;
    User supplier3;
    User[] suppliers;

    User borrower1;
    User borrower2;
    User borrower3;
    User[] borrowers;

    Attacker attacker;

    function setUp() public {
        marketsManager = new MarketsManagerForAave(lendingPoolAddressesProviderAddress);
        positionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress
        );

        fakePositionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress
        );

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(
            lendingPoolAddressesProviderAddress
        );
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());

        protocolDataProvider = IProtocolDataProvider(protocolDataProviderAddress);

        oracle = IPriceOracleGetter(lendingPoolAddressesProvider.getPriceOracle());

        marketsManager.setPositionsManager(address(positionsManager));
        marketsManager.updateLendingPool();
        // !!! WARNING !!!
        // All token added with createMarket must be added in create_custom_price_oracle function.
        marketsManager.createMarket(aDai, WAD, type(uint256).max);
        marketsManager.createMarket(aUsdc, to6Decimals(WAD), type(uint256).max);
        marketsManager.createMarket(aWbtc, 10**4, type(uint256).max);
        marketsManager.createMarket(aUsdt, to6Decimals(WAD), type(uint256).max);
        marketsManager.createMarket(aWmatic, WAD, type(uint256).max);

        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager, marketsManager));

            write_balanceOf(address(suppliers[i]), dai, type(uint256).max / 2);
            write_balanceOf(address(suppliers[i]), usdc, type(uint256).max / 2);
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(positionsManager, marketsManager));

            write_balanceOf(address(borrowers[i]), dai, type(uint256).max / 2);
            write_balanceOf(address(borrowers[i]), usdc, type(uint256).max / 2);
        }
        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];

        attacker = new Attacker(lendingPool);
        write_balanceOf(address(attacker), dai, type(uint256).max / 2);
    }

    function write_balanceOf(
        address who,
        address acct,
        uint256 value
    ) internal {
        hevm.store(acct, keccak256(abi.encode(who, slots[acct])), bytes32(value));
    }

    function mine_blocks(uint256 _count) internal {
        hevm.roll(block.number + _count);
        hevm.warp(block.timestamp + _count * 1000 * AVERAGE_BLOCK_TIME);
    }

    function range(uint256 _amount, address _pool) internal view returns (uint256) {
        return range(_amount, _pool, 1);
    }

    function range(
        uint256 _amount,
        address _pool,
        uint256 div
    ) internal view returns (uint256) {
        _amount %= type(uint64).max / div;
        if (_amount <= positionsManager.threshold(_pool))
            _amount += positionsManager.threshold(_pool);

        return _amount;
    }

    function setNMAXAndCreateSigners(uint16 _NMAX) internal {
        marketsManager.setMaxNumberOfUsersInTree(_NMAX);

        while (borrowers.length < _NMAX) {
            borrowers.push(new User(positionsManager, marketsManager));
            write_balanceOf(address(borrowers[borrowers.length - 1]), dai, type(uint256).max / 2);
            write_balanceOf(address(borrowers[borrowers.length - 1]), usdc, type(uint256).max / 2);

            suppliers.push(new User(positionsManager, marketsManager));
            write_balanceOf(address(suppliers[suppliers.length - 1]), dai, type(uint256).max / 2);
            write_balanceOf(address(suppliers[suppliers.length - 1]), usdc, type(uint256).max / 2);
        }
    }

    // // = Suppliers on Aave (no borrowers) =
    // // ====================================

    // // Suppliers on Aave (no borrowers)
    // // Should have correct balances at the beginning
    // function test_borrowers_have_correct_balance_at_start() public {
    //     (uint256 onPool, uint256 inP2P) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );

    //     assertEq(onPool, 0);
    //     assertEq(inP2P, 0);
    // }

    // // Suppliers on Aave (no borrowers)
    // // Should revert when supply less than the required threshold
    // function testFail_revert_supply_under_threshold() public {
    //     supplier1.supply(aDai, positionsManager.threshold(aDai) - 1);
    // }

    // // Fuzzing
    // // Suppliers on Aave (no borrowers)
    // // Should have the correct balances after supply
    // function test_correct_balance_after_supply(uint16 _amount) public {
    //     if (_amount <= positionsManager.threshold(aDai)) return;

    //     uint256 daiBalanceBefore = borrower1.balanceOf(dai);
    //     uint256 expectedDaiBalanceAfter = daiBalanceBefore - _amount;

    //     borrower1.approve(dai, address(positionsManager), _amount);
    //     borrower1.supply(aDai, _amount);

    //     uint256 daiBalanceAfter = borrower1.balanceOf(dai);
    //     assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

    //     uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
    //     uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(_amount, normalizedIncome);

    //     assertEq(IERC20(aDai).balanceOf(address(positionsManager)), _amount);
    //     (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
    //         aUsdc,
    //         address(positionsManager)
    //     );
    //     assertEq(onPool, expectedSupplyBalanceOnPool);
    //     assertEq(inP2P, 0);
    // }

    // // Suppliers on Aave (no borrowers)
    // // Should be able to withdraw ERC20 right after supply up to max supply balance
    // function test_withdraw_after_supply_part1() public {
    //     uint256 amount = 10 ether;
    //     uint256 daiBalanceBefore1 = supplier1.balanceOf(dai);

    //     supplier1.approve(dai, address(positionsManager), amount);
    //     supplier1.supply(aDai, amount);
    //     uint256 daiBalanceAfter1 = supplier1.balanceOf(dai);
    //     assertEq(daiBalanceAfter1, daiBalanceBefore1 - amount);
    // }

    // function test_withdraw_after_supply_part2() public {
    //     uint256 daiBalanceBefore = supplier1.balanceOf(dai);

    //     test_withdraw_after_supply_part1();

    //     uint256 toWithdraw = get_on_pool_in_underlying(supplier1, aDai, dai);
    //     supplier1.withdraw(aDai, toWithdraw);
    //     uint256 daiBalanceAfter2 = supplier1.balanceOf(dai);
    //     // Check ERC20 balance
    //     assertEq(daiBalanceAfter2, daiBalanceBefore - 10 ether + toWithdraw);

    //     // Check aToken left are only dust in supply balance
    //     (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
    //     assertLt(onPool, 10);
    // }

    // function testFail_withdraw_after_supply_1() public {
    //     test_withdraw_after_supply_part1();

    //     uint256 toWithdraw = get_on_pool_in_underlying(supplier1, aDai, dai);
    //     supplier1.withdraw(aDai, toWithdraw + 1);
    // }

    // function testFail_withdraw_after_supply_2() public {
    //     test_withdraw_after_supply_part1();
    //     test_withdraw_after_supply_part2();

    //     supplier1.withdraw(aDai, 1 ether / 1000);
    // }

    // // Suppliers on Aave (no borrowers)
    // // Should be able to supply more ERC20 after already having supply ERC20
    // function test_supply_more_after_supply() public {
    //     uint256 amount = 10 * 1e18;
    //     uint256 amountToApprove = 10 * 1e18 * 2;
    //     uint256 daiBalanceBefore = supplier1.balanceOf(dai);

    //     supplier1.approve(dai, address(positionsManager), amountToApprove);
    //     supplier1.supply(aDai, amount);
    //     uint256 normalizedIncome1 = lendingPool.getReserveNormalizedIncome(dai);
    //     supplier1.supply(aDai, amount);
    //     uint256 normalizedIncome2 = lendingPool.getReserveNormalizedIncome(dai);

    //     // Check ERC20 balance
    //     uint256 daiBalanceAfter = supplier1.balanceOf(dai);
    //     assertEq(daiBalanceAfter, daiBalanceBefore - amountToApprove);

    //     // Check supply balance
    //     uint256 expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(amount, normalizedIncome1);
    //     uint256 expectedSupplyBalanceOnPool2 = underlyingToScaledBalance(amount, normalizedIncome2);
    //     uint256 expectedSupplyBalanceOnPool = expectedSupplyBalanceOnPool1 +
    //         expectedSupplyBalanceOnPool2;
    //     assertEq(
    //         IAToken(aDai).scaledBalanceOf(address(positionsManager)),
    //         expectedSupplyBalanceOnPool
    //     );

    //     (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
    //     assertEq(onPool, expectedSupplyBalanceOnPool);
    // }

    // // Suppliers on Aave (no borrowers)
    // // Several suppliers should be able to supply and have the correct balances
    // function test_several_suppliers() public {
    //     uint256 amount = 10 * 1e18;
    //     uint256 expectedScaledBalance = 0;

    //     for (uint256 i = 0; i < suppliers.length; i++) {
    //         User supplier = suppliers[i];

    //         uint256 daiBalanceBefore = supplier.balanceOf(dai);
    //         uint256 expectedDaiBalanceAfter = daiBalanceBefore - amount;
    //         supplier.approve(dai, address(positionsManager), amount);
    //         supplier.supply(aDai, amount);
    //         uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
    //         uint256 daiBalanceAfter = supplier.balanceOf(dai);
    //         uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(
    //             amount,
    //             normalizedIncome
    //         );

    //         // Check ERC20 balance
    //         assertEq(daiBalanceAfter, expectedDaiBalanceAfter);
    //         expectedScaledBalance += expectedSupplyBalanceOnPool;

    //         uint256 scaledBalance = IAToken(aDai).scaledBalanceOf(address(positionsManager));
    //         uint256 diff = get_abs_diff(scaledBalance, expectedScaledBalance);

    //         assertEq(diff, 0);
    //         (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
    //             aDai,
    //             address(supplier)
    //         );
    //         assertEq(onPool, expectedSupplyBalanceOnPool);
    //         assertEq(inP2P, 0);
    //     }
    // }

    // // ====================================
    // // = Borrowers on Aave (no suppliers) =
    // // ====================================

    // // Borrowers on Aave (no suppliers)
    // // Should have correct balances at the beginning
    // function test_correct_balances_at_begining() public {
    //     (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );

    //     assertEq(inP2P, 0);
    //     assertEq(onPool, 0);
    // }

    // // Borrowers on Aave (no suppliers)
    // // Should revert when providing 0 as collateral
    // function testFail_revert_when_providing_0_as_collateral() public {
    //     supplier1.supply(aDai, 0);
    // }

    // // Borrowers on Aave (no suppliers)
    // // Should revert when borrow less than threshold
    // function testFail_when_borrow_less_than_threshold() public {
    //     uint256 amount = to6Decimals(positionsManager.threshold(aDai) - 1);
    //     borrower1.approve(dai, address(positionsManager), amount);
    //     borrower1.borrow(aDai, amount);
    // }

    // // Borrowers on Aave (no suppliers)
    // // Should be able to borrow on Aave after providing collateral up to max
    // function test_borrow_on_aave_after_providing_collateral() public {
    //     uint256 amount = to6Decimals(100 ether);
    //     borrower1.approve(usdc, address(positionsManager), amount);
    //     borrower1.supply(aUsdc, amount);

    //     uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
    //     (, uint256 collateralBalanceInScaledBalance) = positionsManager.supplyBalanceInOf(
    //         aUsdc,
    //         address(borrower1)
    //     );
    //     uint256 collateralBalanceInUnderlying = scaledBalanceToUnderlying(
    //         collateralBalanceInScaledBalance,
    //         normalizedIncome
    //     );

    //     (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
    //         .getReserveConfigurationData(dai);
    //     uint256 usdcPrice = oracle.getAssetPrice(usdc);
    //     uint8 usdcDecimals = ERC20(usdc).decimals();
    //     uint256 daiPrice = oracle.getAssetPrice(dai);
    //     uint8 daiDecimals = ERC20(dai).decimals();
    //     uint256 maxToBorrow = (((((collateralBalanceInUnderlying * usdcPrice) / 10**usdcDecimals) *
    //         10**daiDecimals) / daiPrice) * liquidationThreshold) / PERCENT_BASE;
    //     uint256 daiBalanceBefore = borrower1.balanceOf(dai);

    //     // Borrow
    //     borrower1.borrow(aDai, maxToBorrow);
    //     uint256 daiBalanceAfter = borrower1.balanceOf(dai);
    //     uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);

    //     // Check borrower1 balances
    //     assertEq(daiBalanceAfter, daiBalanceBefore + maxToBorrow, "Borrower DAI balance");
    //     (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
    //     uint256 borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
    //         onPool,
    //         normalizedVariableDebt
    //     );

    //     uint256 diff = get_abs_diff(
    //         borrowBalanceOnPoolInUnderlying,
    //         underlyingToAdUnit(maxToBorrow, normalizedVariableDebt)
    //     );
    //     assertEq(diff, 0, "Borrow balance onPool in underlying");

    //     // Check Morpho balances
    //     assertEq(IERC20(dai).balanceOf(address(positionsManager)), 0, "Morpho DAI balance");
    //     assertEq(
    //         IERC20(variableDebtDai).balanceOf(address(positionsManager)),
    //         maxToBorrow,
    //         "Morpho variableDebtDai balance"
    //     );
    // }

    // // Borrowers on Aave (no suppliers)
    // // Should not be able to borrow more than max allowed given an amount of collateral
    // function testFail_borrow_more_than_max_allowed() public {
    //     uint256 amount = to6Decimals(100 ether);
    //     borrower1.approve(usdc, address(positionsManager), amount);
    //     borrower1.supply(aUsdc, amount);

    //     uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
    //     (, uint256 collateralBalanceInScaledBalance) = positionsManager.supplyBalanceInOf(
    //         aUsdc,
    //         address(borrower1)
    //     );
    //     uint256 collateralBalanceInUnderlying = scaledBalanceToUnderlying(
    //         collateralBalanceInScaledBalance,
    //         normalizedIncome
    //     );
    //     (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
    //         .getReserveConfigurationData(dai);
    //     uint256 usdcPrice = oracle.getAssetPrice(usdc);
    //     uint8 usdcDecimals = ERC20(usdc).decimals();
    //     uint256 daiPrice = oracle.getAssetPrice(dai);
    //     uint8 daiDecimals = ERC20(dai).decimals();
    //     uint256 maxToBorrow = (((((collateralBalanceInUnderlying * usdcPrice) / 10**usdcDecimals) *
    //         10**daiDecimals) / daiPrice) * liquidationThreshold) / PERCENT_BASE;
    //     // WARNING: maxToBorrow seems to be not accurate
    //     uint256 moreThanMaxToBorrow = maxToBorrow + 10 ether;

    //     // TODO: fix dust issue
    //     // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
    //     borrower1.borrow(aDai, moreThanMaxToBorrow);
    // }

    // // Borrowers on Aave (no suppliers)
    // // Several borrowers should be able to borrow and have the correct balances
    // function test_several_borrowers_correct_balances() public {
    //     uint256 collateralAmount = to6Decimals(10 ether);
    //     uint256 borrowedAmount = 2 ether;
    //     uint256 expectedMorphoBorrowBalance = 0;
    //     uint256 previousNormalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);

    //     mine_blocks(1);

    //     for (uint256 i = 0; i < borrowers.length; i++) {
    //         User borrower = borrowers[i];

    //         borrower.approve(usdc, address(positionsManager), collateralAmount);
    //         borrower.supply(aUsdc, collateralAmount);
    //         uint256 daiBalanceBefore = borrower.balanceOf(dai);

    //         borrower.borrow(aDai, borrowedAmount);
    //         // We have one block delay from Aave
    //         uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
    //         expectedMorphoBorrowBalance =
    //             (expectedMorphoBorrowBalance * normalizedVariableDebt) /
    //             previousNormalizedVariableDebt +
    //             borrowedAmount;

    //         // All underlyings should have been sent to the borrower
    //         uint256 daiBalanceAfter = borrower.balanceOf(dai);
    //         assertEq(daiBalanceAfter, daiBalanceBefore + borrowedAmount, "Borrower DAI balance");
    //         (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
    //         uint256 borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
    //             onPool,
    //             normalizedVariableDebt
    //         );
    //         assertEq(borrowBalanceOnPoolInUnderlying, borrowedAmount);
    //         // Update previous borrow index
    //         previousNormalizedVariableDebt = normalizedVariableDebt;
    //     }

    //     // Check Morpho balances
    //     assertEq(IERC20(dai).balanceOf(address(positionsManager)), 0, "Morpho DAI balance");

    //     uint256 diffBal = get_abs_diff(
    //         IERC20(variableDebtDai).balanceOf(address(positionsManager)),
    //         expectedMorphoBorrowBalance
    //     );
    //     assertLe(diffBal, 1, "Morpho variableDebtDai balance");
    // }

    // // Borrowers on Aave (no suppliers)
    // // Borrower should be able to repay less than what is on Aave
    // function test_repay_less_than_on_aave() public {
    //     uint256 amount = to6Decimals(100 ether);
    //     borrower1.approve(usdc, address(positionsManager), amount);
    //     borrower1.supply(aUsdc, amount);

    //     uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
    //     (, uint256 collateralBalanceInScaledBalance) = positionsManager.supplyBalanceInOf(
    //         aUsdc,
    //         address(borrower1)
    //     );
    //     uint256 collateralBalanceInUnderlying = scaledBalanceToUnderlying(
    //         collateralBalanceInScaledBalance,
    //         normalizedIncome
    //     );
    //     (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
    //         .getReserveConfigurationData(dai);
    //     uint256 usdcPrice = oracle.getAssetPrice(usdc);
    //     uint8 usdcDecimals = ERC20(usdc).decimals();
    //     uint256 daiPrice = oracle.getAssetPrice(dai);
    //     uint8 daiDecimals = ERC20(dai).decimals();
    //     uint256 maxToBorrow = (((((collateralBalanceInUnderlying * usdcPrice) / 10**usdcDecimals) *
    //         10**daiDecimals) / daiPrice) * liquidationThreshold) / PERCENT_BASE;

    //     emit log_named_uint("maxToBorrow", maxToBorrow);
    //     uint256 daiBalanceBefore = borrower1.balanceOf(dai);
    //     borrower1.borrow(aDai, maxToBorrow);

    //     (, uint256 borrowBalanceOnPool) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );
    //     uint256 normalizeVariableDebt1 = lendingPool.getReserveNormalizedVariableDebt(dai);
    //     uint256 borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
    //         borrowBalanceOnPool,
    //         normalizeVariableDebt1
    //     );
    //     uint256 toRepay = borrowBalanceOnPoolInUnderlying / 2;
    //     borrower1.approve(dai, address(positionsManager), toRepay);
    //     borrower1.repay(aDai, toRepay);
    //     uint256 normalizeVariableDebt2 = lendingPool.getReserveNormalizedVariableDebt(dai);
    //     uint256 daiBalanceAfter = borrower1.balanceOf(dai);

    //     uint256 expectedBalanceOnPool = borrowBalanceOnPool -
    //         underlyingToAdUnit(borrowBalanceOnPoolInUnderlying / 2, normalizeVariableDebt2);

    //     (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
    //     assertEq(onPool, expectedBalanceOnPool);
    //     assertEq(daiBalanceAfter, daiBalanceBefore + maxToBorrow - toRepay);
    // }

    // // ===================================================
    // // = P2P interactions between supplier and borrowers =
    // // ===================================================

    // // P2P interactions between supplier and borrowers
    // // Supplier should withdraw her liquidity while not enough aToken in peer-to-peer contract
    // function test_withdraw_liquidity_while_not_enough_in_p2p() public {
    //     /* TODO: Resolve STACK TOO DEEP */
    //     /*
    //     // Supplier supplies tokens
    //     uint256 supplyAmount = 10 ether;
    //     uint256 expectedDaiBalanceAfter = supplier1.balanceOf(dai) - supplyAmount;
    //     supplier1.approve(dai, address(positionsManager), supplyAmount);
    //     supplier1.supply(aDai, supplyAmount);

    //     // Check ERC20 balance
    //     assertEq(supplier1.balanceOf(dai), expectedDaiBalanceAfter);
    //     uint256 expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(
    //         supplyAmount,
    //         lendingPool.getReserveNormalizedIncome(dai)
    //     );
    //     assertEq(
    //         IAToken(aDai).scaledBalanceOf(address(positionsManager)),
    //         expectedSupplyBalanceOnPool1
    //     );

    //     (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
    //         aDai,
    //         address(supplier1)
    //     );
    //     assertEq(onPool, expectedSupplyBalanceOnPool1);

    //     // Borrower provides collateral
    //     uint256 collateralAmount = to6Decimals(100 ether);
    //     borrower1.approve(usdc, address(positionsManager), collateralAmount);
    //     borrower1.supply(aUsdc, collateralAmount);

    //     // Borrowers borrows supplier1 amount
    //     borrower1.borrow(aDai, supplyAmount);

    //     // Check supplier1 balances
    //     uint256 p2pExchangeRate1 = marketsManager.p2pUnitExchangeRate(aDai);
    //     uint256 expectedSupplyBalanceOnPool2 = expectedSupplyBalanceOnPool1 -
    //         underlyingToScaledBalance(supplyAmount, lendingPool.getReserveNormalizedIncome(dai));
    //     uint256 expectedSupplyBalanceInP2P2 = underlyingToP2PUnit(supplyAmount, p2pExchangeRate1);
    //     (uint256 supplyBalanceInP2P2, uint256 supplyBalanceOnPool2) = positionsManager
    //         .supplyBalanceInOf(aDai, address(supplier1));

    //     assertEq(supplyBalanceOnPool2, expectedSupplyBalanceOnPool2);
    //     assertEq(supplyBalanceInP2P2, expectedSupplyBalanceInP2P2);

    //     // Check borrower1 balances
    //     uint256 expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
    //     (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
    //     assertEq(onPool, 0);
    //     assertEq(inP2P, expectedBorrowBalanceInP2P1);

    //     // Compare remaining to withdraw and the aToken contract balance
    //     marketsManager.updateP2PUnitExchangeRate(aDai);
    //     uint256 p2pExchangeRate2 = marketsManager.p2pUnitExchangeRate(aDai);
    //     uint256 p2pExchangeRate3 = computeNewMorphoExchangeRate(
    //         p2pExchangeRate2,
    //         marketsManager.p2pSPY(aDai),
    //         1,
    //         0
    //     );

    //     (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
    //     uint256 normalizedIncome3 = lendingPool.getReserveNormalizedIncome(dai);
    //     uint256 supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(
    //         onPool,
    //         normalizedIncome3
    //     );
    //     uint256 amountToWithdraw = supplyBalanceOnPoolInUnderlying +
    //         p2pUnitToUnderlying(inP2P, p2pExchangeRate3);
    //     expectedDaiBalanceAfter = supplier1.balanceOf(dai) + amountToWithdraw;
    //     uint256 remainingToWithdraw = amountToWithdraw - supplyBalanceOnPoolInUnderlying;
    //     uint256 aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(
    //         IERC20(aDai).balanceOf(address(positionsManager)),
    //         normalizedIncome3
    //     );
    //     assertGt(remainingToWithdraw, aTokenContractBalanceInUnderlying);

    //     // Expected borrow balances
    //     uint256 expectedMorphoBorrowBalance = remainingToWithdraw +
    //         aTokenContractBalanceInUnderlying -
    //         supplyBalanceOnPoolInUnderlying;

    //     // Withdraw
    //     supplier1.withdraw(aDai, amountToWithdraw);
    //     uint256 expectedBorrowerBorrowBalanceOnPool = underlyingToAdUnit(
    //         expectedMorphoBorrowBalance,
    //         lendingPool.getReserveNormalizedVariableDebt(dai)
    //     );

    //     // Check borrow balance of Morpho
    //     assertEq(
    //         IERC20(variableDebtDai).balanceOf(address(positionsManager)),
    //         expectedMorphoBorrowBalance
    //     );

    //     // Check supplier1 underlying balance
    //     assertEq(supplier1.balanceOf(dai), expectedDaiBalanceAfter);

    //     // Check supply balances of supplier1
    //     (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
    //     assertEq(onPool, 0);
    //     assertEq(inP2P, 0);

    //     // Check borrow balances of borrower1
    //     (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(borrower1));
    //     assertEq(onPool, expectedBorrowerBorrowBalanceOnPool);
    //     assertEq(inP2P, 0);
    //     */
    // }

    // // P2P interactions between supplier and borrowers
    // // Supplier should withdraw her liquidity while enough aDaiToken in peer-to-peer contract
    // function test_withdraw_liquidity_while_enough_adaitoken_in_p2p() public {
    //     // TODO
    // }

    // // P2P interactions between supplier and borrowers
    // // Borrower in peer-to-peer only, should be able to repay all borrow amount
    // function test_borrower_in_p2p_only_repay_all_borrow() public {
    //     // Supplier supplies tokens
    //     uint256 supplyAmount = 10 ether;
    //     supplier1.approve(dai, address(positionsManager), supplyAmount);
    //     supplier1.supply(aDai, supplyAmount);

    //     // Borrower borrows half of the tokens
    //     uint256 collateralAmount = to6Decimals(100 ether);
    //     uint256 daiBalanceBefore = borrower1.balanceOf(dai);
    //     uint256 toBorrow = supplyAmount / 2;

    //     borrower1.approve(usdc, address(positionsManager), collateralAmount);
    //     borrower1.supply(aUsdc, collateralAmount);
    //     borrower1.borrow(aDai, toBorrow);

    //     (uint256 borrowerBalanceInP2P, ) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );
    //     uint256 p2pSPY = marketsManager.p2pSPY(aDai);
    //     marketsManager.updateP2PUnitExchangeRate(aDai);
    //     uint256 p2pUnitExchangeRate = marketsManager.p2pUnitExchangeRate(aDai);
    //     uint256 p2pExchangeRate = computeNewMorphoExchangeRate(
    //         p2pUnitExchangeRate,
    //         p2pSPY,
    //         AVERAGE_BLOCK_TIME,
    //         0
    //     );
    //     uint256 toRepay = p2pUnitToUnderlying(borrowerBalanceInP2P, p2pExchangeRate);
    //     uint256 expectedDaiBalanceAfter = daiBalanceBefore + toBorrow - toRepay;
    //     uint256 previousMorphoScaledBalance = IAToken(aDai).scaledBalanceOf(
    //         address(positionsManager)
    //     );

    //     // Repay
    //     borrower1.approve(dai, address(positionsManager), toRepay);
    //     borrower1.repay(aDai, toRepay);
    //     uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
    //     uint256 expectedMorphoScaledBalance = previousMorphoScaledBalance +
    //         underlyingToScaledBalance(toRepay, normalizedIncome);

    //     // Check borrower1 balances
    //     uint256 daiBalanceAfter = borrower1.balanceOf(dai);
    //     assertEq(daiBalanceAfter, expectedDaiBalanceAfter);
    //     // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
    //     (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
    //     assertEq(onPool, 0);
    //     // Commented here due to the pow function issue
    //     // expect(removeDigitsBigNumber(1, (await positionsManager.borrowBalanceInOf(address(borrower1))).inP2P)).to.equal(0);

    //     // Check Morpho balances
    //     assertEq(
    //         IAToken(aDai).scaledBalanceOf(address(positionsManager)),
    //         expectedMorphoScaledBalance
    //     );
    //     assertEq(IERC20(variableDebtDai).balanceOf(address(positionsManager)), 0);
    // }

    // // P2P interactions between supplier and borrowers
    // // Borrower in peer-to-peer and on Aave, should be able to repay all borrow amount
    // function test_borrower_in_p2p_and_aave_repay_all_borrow() public {
    //     /* TODO STACK TOO DEEP
    //     // Supplier supplys tokens
    //     uint256 supplyAmount = 10 ether;
    //     uint256 amountToApprove = 100000000 ether;
    //     supplier1.approve(dai, address(positionsManager), supplyAmount);
    //     supplier1.supply(aDai, supplyAmount);

    //     // Borrower borrows two times the amount of tokens;
    //     uint256 collateralAmount = to6Decimals(100 ether);
    //     borrower1.approve(usdc, address(positionsManager), collateralAmount);
    //     borrower1.supply(aUsdc, collateralAmount);
    //     uint256 daiBalanceBefore = borrower1.balanceOf(dai);
    //     uint256 toBorrow = supplyAmount * 2;
    //     (, uint256 supplyBalanceOnPool) = positionsManager.supplyBalanceInOf(
    //         aDai,
    //         address(supplier1)
    //     );
    //     borrower1.borrow(aDai, toBorrow);

    //     uint256 expectedMorphoBorrowBalance1 = toBorrow -
    //         scaledBalanceToUnderlying(
    //             supplyBalanceOnPool,
    //             lendingPool.getReserveNormalizedIncome(dai)
    //         );
    //     assertEq(
    //         IERC20(variableDebtDai).balanceOf(address(positionsManager)),
    //         expectedMorphoBorrowBalance1
    //     );
    //     borrower1.approve(dai, address(positionsManager), amountToApprove);

    //     (uint256 borrowerBalanceInP2P, ) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );
    //     uint256 p2pSPY = marketsManager.p2pSPY(aDai);
    //     uint256 p2pUnitExchangeRate = marketsManager.p2pUnitExchangeRate(aDai);
    //     uint256 p2pExchangeRate = computeNewMorphoExchangeRate(
    //         p2pUnitExchangeRate,
    //         p2pSPY,
    //         AVERAGE_BLOCK_TIME * 2,
    //         0
    //     );
    //     uint256 borrowerBalanceInP2PInUnderlying = p2pUnitToUnderlying(
    //         borrowerBalanceInP2P,
    //         p2pExchangeRate
    //     );

    //     // Compute how much to repay
    //     uint256 normalizeVariableDebt1 = lendingPool.getReserveNormalizedVariableDebt(dai);
    //     (, uint256 borrowerBalanceOnPool) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );
    //     uint256 toRepay = aDUnitToUnderlying(borrowerBalanceOnPool, normalizeVariableDebt1) +
    //         borrowerBalanceInP2PInUnderlying;
    //     uint256 previousMorphoScaledBalance = IAToken(aDai).scaledBalanceOf(
    //         address(positionsManager)
    //     );

    //     // Repay
    //     borrower1.approve(dai, address(positionsManager), toRepay);
    //     borrower1.repay(aDai, toRepay);
    //     uint256 normalizedIncome2 = lendingPool.getReserveNormalizedIncome(dai);
    //     uint256 expectedMorphoScaledBalance = previousMorphoScaledBalance +
    //         underlyingToScaledBalance(borrowerBalanceInP2PInUnderlying, normalizedIncome2);

    //     // Check borrower1 balances
    //     assertEq(borrower1.balanceOf(dai), daiBalanceBefore + toBorrow - toRepay);
    //     (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );
    //     assertEq(onPool, 0);
    //     assertLt(inP2P, 1000000000000);

    //     // Check Morpho balances
    //     assertEq(
    //         IAToken(aDai).scaledBalanceOf(address(positionsManager)),
    //         expectedMorphoScaledBalance
    //     );

    //     // Issue here: we cannot access the most updated borrow balance as it's updated during the repayBorrow on Aave.
    //     // const expectedMorphoBorrowBalance2 = morphoBorrowBalanceBefore2.sub(borrowerBalanceOnPool.mul(normalizeVariableDebt2).div(WAD));
    //     // expect(removeDigitsBigNumber(3, await aToken.callStatic.borrowBalanceStored(address(positionsManager)))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowBalance2));
    //     */
    // }

    // // P2P interactions between supplier and borrowers
    // // Supplier should be connected to borrowers on pool when supplying
    // function test_supplier_connected_to_borrowers_on_pool_when_supplying() public {
    //     uint256 collateralAmount = to6Decimals(100 ether);
    //     uint256 supplyAmount = 100 ether;
    //     uint256 borrowAmount = 30 ether;

    //     uint256[] memory borrowersBorrowBalanceOnPool = new uint256[](borrowers.length);
    //     uint256 borrowersBorrowBalanceOnPoolTotal = 0;
    //     for (uint256 i = 0; i < borrowers.length; i++) {
    //         // borrower borrows
    //         borrowers[i].approve(usdc, address(positionsManager), collateralAmount);
    //         borrowers[i].supply(aUsdc, collateralAmount);
    //         borrowers[i].borrow(aDai, borrowAmount);
    //         (, uint256 borrowerBorrowBalanceOnPool) = positionsManager.borrowBalanceInOf(
    //             aDai,
    //             address(borrowers[i])
    //         );
    //         borrowersBorrowBalanceOnPool[i] = borrowerBorrowBalanceOnPool;
    //         borrowersBorrowBalanceOnPoolTotal += borrowerBorrowBalanceOnPool;
    //     }

    //     // supplier1 supply
    //     supplier1.approve(dai, address(positionsManager), supplyAmount);
    //     supplier1.supply(aDai, supplyAmount);
    //     uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
    //     uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
    //     uint256 p2pUnitExchangeRate = marketsManager.p2pUnitExchangeRate(aDai);

    //     // Check balances
    //     (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = positionsManager
    //         .supplyBalanceInOf(aDai, address(supplier1));
    //     uint256 underlyingMatched = aDUnitToUnderlying(
    //         borrowersBorrowBalanceOnPoolTotal,
    //         normalizedVariableDebt
    //     );

    //     uint256 expectedSupplyBalanceInP2P = underlyingToAdUnit(
    //         underlyingMatched,
    //         p2pUnitExchangeRate
    //     );
    //     uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(
    //         supplyAmount - underlyingMatched,
    //         normalizedIncome
    //     );

    //     assertEq(supplyBalanceInP2P, expectedSupplyBalanceInP2P);
    //     assertEq(supplyBalanceOnPool, expectedSupplyBalanceOnPool);

    //     for (uint256 i = 0; i < borrowers.length; i++) {
    //         (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrowers[i]));
    //         assertLe(onPool, 1);
    //     }
    // }

    // // P2P interactions between supplier and borrowers
    // // Borrower should be connected to suppliers on pool in peer-to-peer when borrowing
    // function test_borrower_connected_to_suppliers_on_pool_in_p2p_when_borrowing() public {
    //     uint256 collateralAmount = to6Decimals(140 ether);
    //     uint256 supplyAmount = 30 ether;
    //     uint256 borrowAmount = 100 ether;

    //     uint256[] memory suppliersBorrowBalanceOnPool = new uint256[](suppliers.length);
    //     uint256 suppliersBorrowBalanceOnPoolTotal = 0;
    //     for (uint256 i = 0; i < suppliers.length; i++) {
    //         // supplier supplies
    //         suppliers[i].approve(dai, address(positionsManager), supplyAmount);
    //         suppliers[i].supply(aDai, supplyAmount);
    //         (, uint256 supplierBorrowBalanceOnPool) = positionsManager.supplyBalanceInOf(
    //             aDai,
    //             address(suppliers[i])
    //         );
    //         suppliersBorrowBalanceOnPool[i] = supplierBorrowBalanceOnPool;
    //         suppliersBorrowBalanceOnPoolTotal += supplierBorrowBalanceOnPool;
    //     }

    //     // borrower1 borrows
    //     borrower1.approve(usdc, address(positionsManager), collateralAmount);
    //     borrower1.supply(aUsdc, collateralAmount);
    //     borrower1.borrow(aDai, borrowAmount);
    //     uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
    //     uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
    //     uint256 p2pUnitExchangeRate = marketsManager.p2pUnitExchangeRate(aDai);

    //     // Check balances
    //     (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );
    //     uint256 underlyingMatched = scaledBalanceToUnderlying(
    //         suppliersBorrowBalanceOnPoolTotal,
    //         normalizedIncome
    //     );

    //     uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
    //         underlyingMatched,
    //         p2pUnitExchangeRate
    //     );
    //     uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
    //         borrowAmount - underlyingMatched,
    //         normalizedVariableDebt
    //     );

    //     assertEq(inP2P, expectedBorrowBalanceInP2P);
    //     assertEq(onPool, expectedBorrowBalanceOnPool);

    //     for (uint256 i = 0; i < suppliers.length; i++) {
    //         (, onPool) = positionsManager.supplyBalanceInOf(aDai, address(suppliers[i]));
    //         assertLe(onPool, 1);
    //     }
    // }

    // // ====================
    // // = Test liquidation =
    // // ====================

    // function create_custom_price_oracle() public returns (SimplePriceOracle) {
    //     SimplePriceOracle customOracle = new SimplePriceOracle();

    //     hevm.store(
    //         address(lendingPoolAddressesProvider),
    //         keccak256(abi.encode(bytes32("PRICE_ORACLE"), 2)),
    //         bytes32(uint256(uint160(address(customOracle))))
    //     );

    //     // !!! WARNING !!! All tokens added with createMarket must be set
    //     customOracle.setDirectPrice(dai, oracle.getAssetPrice(dai));
    //     customOracle.setDirectPrice(usdc, oracle.getAssetPrice(usdc));
    //     customOracle.setDirectPrice(usdt, oracle.getAssetPrice(usdt));
    //     customOracle.setDirectPrice(wbtc, oracle.getAssetPrice(wbtc));
    //     customOracle.setDirectPrice(wmatic, oracle.getAssetPrice(wmatic));

    //     return customOracle;
    // }

    // function test_create_custom_price_oracle() public {
    //     assertEq(lendingPoolAddressesProvider.getPriceOracle(), address(oracle));
    //     SimplePriceOracle customOracle = create_custom_price_oracle();

    //     assertEq(lendingPoolAddressesProvider.getPriceOracle(), address(customOracle));

    //     assertEq(customOracle.getAssetPrice(dai), oracle.getAssetPrice(dai));
    //     assertEq(customOracle.getAssetPrice(usdc), oracle.getAssetPrice(usdc));
    //     assertEq(customOracle.getAssetPrice(usdt), oracle.getAssetPrice(usdt));
    //     assertEq(customOracle.getAssetPrice(wbtc), oracle.getAssetPrice(wbtc));
    //     assertEq(customOracle.getAssetPrice(wmatic), oracle.getAssetPrice(wmatic));
    // }

    // // Test liquidation
    // // Borrower should be liquidated while supply (collateral) is only on Aave
    // function test_borrower_liquidated_while_supply_on_aave() public {
    //     SimplePriceOracle customOracle = create_custom_price_oracle();

    //     // Deposit
    //     uint256 amount = to6Decimals(100 ether);
    //     borrower1.approve(usdc, address(positionsManager), amount);
    //     borrower1.supply(aUsdc, amount);

    //     uint256 collateralInUnderlying = get_on_pool_in_underlying(borrower1, aUsdc, usdc);
    //     uint256 maxToBorrow = get_max_to_borrow(collateralInUnderlying, usdc, dai, customOracle);

    //     // Borrow DAI
    //     borrower1.borrow(aDai, maxToBorrow);
    //     (, uint256 collateralBalanceBefore) = positionsManager.supplyBalanceInOf(
    //         aUsdc,
    //         address(borrower1)
    //     );
    //     (, uint256 borrowBalanceBefore) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );

    //     // Set price oracle
    //     customOracle.setDirectPrice(dai, 1070182920000000000);

    //     // Mine block
    //     mine_blocks(1);

    //     // Liquidate
    //     uint256 toRepay = maxToBorrow / 2;
    //     User liquidator = borrower3;
    //     liquidator.approve(dai, address(positionsManager), toRepay);
    //     uint256 usdcBalanceBefore = liquidator.balanceOf(usdc);
    //     uint256 daiBalanceBefore = liquidator.balanceOf(dai);
    //     liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);

    //     // Liquidation parameters
    //     uint256 amountToSeize = get_amount_to_seize(toRepay, usdc, dai, customOracle);

    //     // Check balances
    //     (, uint256 onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(borrower1));
    //     assertEq(
    //         onPool,
    //         collateralBalanceBefore -
    //             underlyingToScaledBalance(
    //                 amountToSeize,
    //                 lendingPool.getReserveNormalizedIncome(usdc)
    //             ),
    //         "Borrower USDC supplied balance on pool"
    //     );

    //     (, onPool) = positionsManager.borrowBalanceInOf(aUsdc, address(borrower1));
    //     assertEq(
    //         onPool,
    //         borrowBalanceBefore -
    //             underlyingToAdUnit(toRepay, lendingPool.getReserveNormalizedVariableDebt(dai)),
    //         "Borrower USDC borrowed balance on pool"
    //     );

    //     assertEq(
    //         liquidator.balanceOf(usdc),
    //         usdcBalanceBefore + amountToSeize,
    //         "Liquidator USDC balance after liquidation"
    //     );
    //     assertEq(
    //         liquidator.balanceOf(dai),
    //         daiBalanceBefore - toRepay,
    //         "Liquidator DAI balance after liquidation"
    //     );
    // }

    // // Test liquidation
    // // Borrower should be liquidated while supply (collateral) is on Aave and in peer-to-peer
    // function test_borrower_liquidated_while_supply_on_aave_and_p2p() public {
    //     /* STACK TOO DEEP
    //     // Deploy custom price oracle
    //     SimplePriceOracle customOracle = create_custom_price_oracle();

    //     // supplier1 supplies DAI
    //     supplier1.approve(dai, address(positionsManager), 200 ether);
    //     supplier1.supply(aDai, 200 ether);

    //     // borrower1 supplies USDC as supply (collateral)
    //     uint256 amount = to6Decimals(100 ether);
    //     borrower1.approve(usdc, address(positionsManager), amount);
    //     borrower1.supply(aUsdc, amount);

    //     // borrower2 borrows part of supply of borrower1 -> borrower1 has supply in peer-to-peer and on Aave
    //     uint256 toBorrow = amount;
    //     borrower2.approve(wbtc, address(positionsManager), 10**8);
    //     borrower2.supply(aWbtc, 10**8);
    //     borrower2.borrow(aUsdc, toBorrow);

    //     // borrower1 borrows DAI
    //     (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
    //         aUsdc,
    //         address(borrower1)
    //     );

    //     uint256 supplyBalanceInUnderlying = scaledBalanceToUnderlying(
    //         onPool,
    //         lendingPool.getReserveNormalizedIncome(usdc)
    //     ) + p2pUnitToUnderlying(inP2P, marketsManager.p2pUnitExchangeRate(aUsdc));

    //     uint256 maxToBorrow = get_max_to_borrow(supplyBalanceInUnderlying, usdc, dai, customOracle);
    //     borrower1.borrow(aDai, maxToBorrow);
    //     (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(borrower1));
    //     (uint256 borrowBalanceInP2PBefore, ) = positionsManager.borrowBalanceInOf(
    //         aDai,
    //         address(borrower1)
    //     );

    //     // Set price oracle
    //     customOracle.setDirectPrice(dai, 1070182920000000000);

    //     // Mine block
    //     mine_blocks(1);

    //     // liquidator liquidates borrower1's position
    //     uint256 toRepay = (maxToBorrow * LIQUIDATION_CLOSE_FACTOR_PERCENT) / PERCENT_BASE;
    //     User liquidator = borrower3;
    //     liquidator.approve(dai, address(positionsManager), toRepay);
    //     uint256 usdcBalanceBefore = liquidator.balanceOf(usdc);
    //     uint256 daiBalanceBefore = liquidator.balanceOf(dai);
    //     liquidator.liquidate(aDai, aUsdc, address(borrower1), toRepay);

    //     // Liquidation parameters
    //     uint256 amountToSeize = get_amount_to_seize(toRepay, usdc, dai, customOracle);
    //     uint256 expectedCollateralBalanceInP2PAfter = inP2P -
    //         amountToSeize -
    //         scaledBalanceToUnderlying(onPool, lendingPool.getReserveNormalizedIncome(usdc));
    //     uint256 expectedBorrowBalanceInP2PAfter = borrowBalanceInP2PBefore -
    //         underlyingToP2PUnit(toRepay, marketsManager.p2pUnitExchangeRate(aDai));
    //     uint256 expectedUsdcBalanceAfter = usdcBalanceBefore + amountToSeize;
    //     uint256 expectedDaiBalanceAfter = daiBalanceBefore - toRepay;

    //     // Check liquidatee balances
    //     (inP2P, onPool) = positionsManager.supplyBalanceInOf(aUsdc, address(borrower1));
    //     assertEq(onPool, 0);
    //     assertEq(inP2P, expectedCollateralBalanceInP2PAfter);

    //     (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
    //     assertEq(onPool, 0);
    //     assertEq(inP2P, expectedBorrowBalanceInP2PAfter);

    //     // Check liquidator balances
    //     uint256 diff = get_abs_diff(liquidator.balanceOf(usdc), expectedUsdcBalanceAfter);
    //     assertEq(diff, 0);
    //     assertEq(liquidator.balanceOf(dai), expectedDaiBalanceAfter);
    //     */
    // }

    // // =============
    // // = Cap value =
    // // =============

    // // Cap Value
    // // Should be possible to supply up to cap value
    // function supply_up_to_cap_value_prepare() public {
    //     marketsManager.updateCapValue(aDai, 2 ether);

    //     supplier1.approve(dai, address(positionsManager), 3 ether);
    // }

    // function test_supply_up_to_cap_value_1() public {
    //     supply_up_to_cap_value_prepare();

    //     supplier1.supply(aDai, 2 ether);
    // }

    // function testFail_supply_up_to_cap_value_2() public {
    //     supply_up_to_cap_value_prepare();

    //     supplier1.supply(aDai, 100 ether);
    // }

    // function testFail_supply_up_to_cap_value_3() public {
    //     supply_up_to_cap_value_prepare();

    //     supplier1.supply(aDai, 1);
    // }

    // // =========================
    // // = Test claiming rewards =
    // // =========================

    // // Test claiming rewards
    // // Anyone should be able to claim rewards on several markets
    // function test_claim_rewards_on_several_markets() public {
    //     uint256 toSupply = 100 ether;
    //     uint256 toBorrow = to6Decimals(50 ether);

    //     address owner = marketsManager.owner();
    //     uint256 rewardTokenBalanceBefore = IERC20(wmatic).balanceOf(owner);
    //     supplier1.approve(dai, address(positionsManager), toSupply);
    //     supplier1.supply(aDai, toSupply);
    //     supplier1.borrow(aUsdc, toBorrow);

    //     // Mine 1000 blocks
    //     mine_blocks(1000);

    //     address[] memory tokens = new address[](1);
    //     tokens[0] = variableDebtUsdc;
    //     supplier1.claimRewards(tokens);
    //     uint256 rewardTokenBalanceAfter1 = IERC20(wmatic).balanceOf(owner);
    //     assertGt(rewardTokenBalanceAfter1, rewardTokenBalanceBefore);

    //     tokens[0] = aDai;
    //     borrower1.claimRewards(tokens);
    //     uint256 rewardTokenBalanceAfter2 = IERC20(wmatic).balanceOf(owner);
    //     assertGt(rewardTokenBalanceAfter2, rewardTokenBalanceAfter1);
    // }

    // // ================
    // // = Test attacks =
    // // ================

    // // Test attacks
    // // Should not be possible to withdraw amount if the position turns to be under-collateralized
    // function testFail_withdraw_amount_position_under_collateralized() public {
    //     uint256 toSupply = 100 ether;
    //     uint256 toBorrow = to6Decimals(50 ether);

    //     // supplier1 deposits collateral
    //     supplier1.approve(dai, address(positionsManager), toSupply);
    //     supplier1.supply(aDai, toSupply);

    //     // supplier2 deposits collateral
    //     supplier2.approve(dai, address(positionsManager), toSupply);
    //     supplier2.supply(aDai, toSupply);

    //     // supplier1 tries to withdraw more than allowed
    //     supplier1.borrow(aUsdc, toBorrow);
    //     supplier1.withdraw(aDai, toSupply);
    // }

    // // Test attacks
    // // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    // function test_withdraw_amount_while_attacker_send_atoken_to_morpho() public {
    //     uint256 toSupply = 100 ether;
    //     uint256 toSupplyCollateral = to6Decimals(200 ether);
    //     uint256 toBorrow = toSupply;

    //     // attacker sends aToken to positionsManager contract
    //     attacker.approve(dai, address(lendingPool), toSupply);
    //     attacker.deposit(dai, toSupply, address(attacker), 0);
    //     attacker.transfer(dai, address(positionsManager), toSupply);

    //     // supplier1 deposits collateral
    //     supplier1.approve(dai, address(positionsManager), toSupply);
    //     supplier1.supply(aDai, toSupply);

    //     // borrower1 deposits collateral
    //     borrower1.approve(usdc, address(positionsManager), toSupplyCollateral);
    //     borrower1.supply(aUsdc, toSupplyCollateral);

    //     // supplier1 tries to withdraw
    //     borrower1.borrow(aDai, toBorrow);
    //     supplier1.withdraw(aDai, toSupply);
    // }

    // // ===================
    // // = Other functions =
    // // ===================

    // function get_on_pool_in_underlying(
    //     User _user,
    //     address _aToken,
    //     address _token
    // ) internal view returns (uint256) {
    //     (, uint256 onPool) = positionsManager.supplyBalanceInOf(_aToken, address(_user));

    //     uint256 inUnderlying = scaledBalanceToUnderlying(
    //         onPool,
    //         lendingPool.getReserveNormalizedIncome(_token)
    //     );

    //     return inUnderlying;
    // }

    // function get_max_to_borrow(
    //     uint256 _collateralInUnderlying,
    //     address _suppliedAsset,
    //     address _borrowedAsset,
    //     SimplePriceOracle _oracle
    // ) internal view returns (uint256) {
    //     (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
    //         .getReserveConfigurationData(_borrowedAsset);
    //     uint256 maxToBorrow = (((((_collateralInUnderlying *
    //         _oracle.getAssetPrice(_suppliedAsset)) / 10**ERC20(_suppliedAsset).decimals()) *
    //         10**ERC20(_borrowedAsset).decimals()) / _oracle.getAssetPrice(_borrowedAsset)) *
    //         liquidationThreshold) / PERCENT_BASE;
    //     return maxToBorrow;
    // }

    // function get_amount_to_seize(
    //     uint256 _toRepay,
    //     address _suppliedAsset,
    //     address _borrowedAsset,
    //     SimplePriceOracle _oracle /*view*/
    // ) internal returns (uint256) {
    //     (, , , uint256 liquidationBonus, , , , , , ) = protocolDataProvider
    //         .getReserveConfigurationData(_borrowedAsset);

    //     emit log_named_uint("toRepay", _toRepay);

    //     uint256 collateralAssetPrice = _oracle.getAssetPrice(_suppliedAsset);
    //     emit log_named_uint("collateralAssetPrice", collateralAssetPrice);
    //     uint256 borrowedAssetPrice = _oracle.getAssetPrice(_borrowedAsset);
    //     emit log_named_uint("borrowedAssetPrice", borrowedAssetPrice);
    //     uint256 amountToSeize = (((((_toRepay * borrowedAssetPrice) /
    //         10**ERC20(_borrowedAsset).decimals()) * 10**ERC20(_suppliedAsset).decimals()) /
    //         collateralAssetPrice) * liquidationBonus) / PERCENT_BASE;

    //     emit log_named_uint("amountToSeize", amountToSeize);
    //     return amountToSeize;
    // }
}
