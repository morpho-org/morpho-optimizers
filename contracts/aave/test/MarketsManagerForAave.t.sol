// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

// Display logs:
// emit log_named_<type>("comarketsManagerentaire", value);
// Example:
// emit log_named_uint("supplier1", supplier1.balanceOf(usdc));

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

contract MarketsManagerForAaveTest is DSTest, Config, Utils {
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

    User borrower1;
    User borrower2;
    User borrower3;

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
        marketsManager.setLendingPool();
        marketsManager.createMarket(aDai, WAD, type(uint256).max);
        marketsManager.createMarket(aUsdc, to6Decimals(WAD), type(uint256).max);

        supplier1 = new User(positionsManager, marketsManager);
        supplier2 = new User(positionsManager, marketsManager);
        supplier3 = new User(positionsManager, marketsManager);

        write_balanceOf(address(supplier1), dai, 100 ether);
        write_balanceOf(address(supplier2), dai, 100 ether);
        write_balanceOf(address(supplier3), dai, 100 ether);

        borrower1 = new User(positionsManager, marketsManager);
        borrower2 = new User(positionsManager, marketsManager);
        borrower3 = new User(positionsManager, marketsManager);

        write_balanceOf(address(borrower1), dai, 100 ether);
        write_balanceOf(address(borrower1), usdc, 100 ether);
        write_balanceOf(address(borrower2), dai, 100 ether);
        write_balanceOf(address(borrower2), usdc, 100 ether);
        write_balanceOf(address(borrower3), dai, 100 ether);
        write_balanceOf(address(borrower3), usdc, 100 ether);

        attacker = new Attacker(lendingPool);
        write_balanceOf(address(attacker), dai, 100 ether);
    }

    function write_balanceOf(
        address who,
        address acct,
        uint256 value
    ) internal {
        hevm.store(acct, keccak256(abi.encode(who, slots[acct])), bytes32(value));
    }

    // ==============
    // = Deployment =
    // ==============

    // Deployment
    // Should deploy the contract with the right values
    function test_deploy_contract() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(dai);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;

        assertEq(marketsManager.p2pSPY(aDai), expectedSPY);
        assertEq(marketsManager.p2pUnitExchangeRate(aDai), RAY);
        assertEq(positionsManager.threshold(aDai), WAD);
    }

    // ========================
    // = Governance functions =
    // ========================

    // Governance functions
    // Should revert when at least when a market in input is not a real market
    function testFail_revert_on_not_real_market() public {
        marketsManager.createMarket(usdt, WAD, type(uint256).max);
    }

    // Governance functions
    // Only Owner should be able to create markets in peer-to-peer
    function testFail_only_owner_can_create_markets_1() public {
        supplier1.createMarket(usdt, WAD, type(uint256).max);
    }

    function testFail_only_owner_can_create_markets_2() public {
        borrower1.createMarket(usdt, WAD, type(uint256).max);
    }

    function test_only_owner_can_create_markets() public {
        marketsManager.createMarket(aWeth, WAD, type(uint256).max);
    }

    // Governance functions
    // marketsManagerForAave should not be changed after already set by Owner
    function testFail_marketsManager_should_not_be_changed() public {
        marketsManager.setPositionsManager(address(fakePositionsManager));
    }

    // Governance functions
    // Only Owner should be able to update cap value
    function test_only_owner_can_update_cap_value() public {
        uint256 newCapValue = 2 * 1e18;
        marketsManager.updateCapValue(aUsdc, newCapValue);
    }

    function testFail_only_owner_can_update_cap_value_1() public {
        uint256 newCapValue = 2 * 1e18;
        supplier1.updateCapValue(aUsdc, newCapValue);
    }

    function testFail_only_owner_can_update_cap_value_2() public {
        uint256 newCapValue = 2 * 1e18;
        borrower1.updateCapValue(aUsdc, newCapValue);
    }

    // Governance functions
    // Should create a market the with right values
    function test_create_market_with_right_values() public {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(aave);
        uint256 expectedSPY = (data.currentLiquidityRate + data.currentVariableBorrowRate) /
            2 /
            SECOND_PER_YEAR;
        marketsManager.createMarket(aAave, WAD, type(uint256).max);

        assertTrue(marketsManager.isCreated(aAave));
        assertEq(marketsManager.p2pSPY(aAave), expectedSPY);
        assertEq(marketsManager.p2pUnitExchangeRate(aAave), RAY);
    }

    // Governance functions
    // Should update NMAX
    function test_should_update_nmax() public {
        uint16 newNMAX = 3000;

        marketsManager.setMaxNumberOfUsersInTree(newNMAX);
        assertEq(positionsManager.NMAX(), newNMAX);
    }

    function testFail_should_update_nmax_1() public {
        supplier1.setMaxNumberOfUsersInTree(3000);
    }

    function testFail_should_update_nmax_2() public {
        borrower1.setMaxNumberOfUsersInTree(3000);
    }

    function testFail_should_update_nmax_3() public {
        positionsManager.setMaxNumberOfUsersInTree(3000);
    }

    // ====================================
    // = Suppliers on Aave (no borrowers) =
    // ====================================

    // Suppliers on Aave (no borrowers)
    // Should have correct balances at the beginning
    function test_borrowers_have_correct_balance_at_start() public {
        (uint256 onPool, uint256 inP2P) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
    }

    // Suppliers on Aave (no borrowers)
    // Should revert when supply less than the required threshold
    function testFail_revert_supply_under_threshold() public {
        supplier1.supply(aDai, positionsManager.threshold(aDai) - 1);
    }

    // Fuzzing
    // Suppliers on Aave (no borrowers)
    // Should have the correct balances after supply
    function test_correct_balance_after_supply(uint16 _amount) public {
        if (_amount <= positionsManager.threshold(aDai)) return;

        uint256 daiBalanceBefore = borrower1.balanceOf(dai);
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - _amount;

        borrower1.approve(dai, address(positionsManager), _amount);
        borrower1.supply(aDai, _amount);

        uint256 daiBalanceAfter = borrower1.balanceOf(dai);
        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(_amount, normalizedIncome);

        assertEq(IERC20(aDai).balanceOf(address(positionsManager)), _amount);
        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(positionsManager)
        );
        assertEq(onPool, expectedSupplyBalanceOnPool);
        assertEq(inP2P, 0);
    }

    // Suppliers on Aave (no borrowers)
    // Should be able to withdraw ERC20 right after supply up to max supply balance
    function test_withdraw_after_supply() public {
        uint256 amount = 10 * 1e18;
        uint256 daiBalanceBefore1 = supplier1.balanceOf(dai);

        supplier1.approve(dai, address(positionsManager), amount);
        supplier1.supply(aDai, amount);
        uint256 daiBalanceAfter1 = supplier1.balanceOf(dai);
        assertEq(daiBalanceAfter1, daiBalanceBefore1 - amount);

        (, uint256 supplyBalanceOnPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        uint256 normalizedIncome1 = lendingPool.getReserveNormalizedIncome(dai);
        uint256 toWithdraw1 = scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome1);

        // TODO: improve this test to prevent attacks
        //await expect(positionsManagerForAave.connect(supplier1).withdraw(toWithdraw1.add(utils.parseUnits('0.001')).toString())).to.be.reverted;

        // Here we must calculate the next normalized income
        uint256 normalizedIncome2 = lendingPool.getReserveNormalizedIncome(dai);
        uint256 toWithdraw2 = scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome2);
        supplier1.withdraw(aDai, toWithdraw2);
        uint256 daiBalanceAfter2 = supplier1.balanceOf(dai);
        // Check ERC20 balance
        assertEq(daiBalanceAfter2, daiBalanceBefore1 - amount + toWithdraw2);

        // Check aToken left are only dust in supply balance
        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertLt(onPool, 10);
    }

    function testFail_withdraw_after_supply() public {
        test_withdraw_after_supply();

        supplier1.withdraw(aDai, (1 / 1000) * 1e18);
    }

    // Suppliers on Aave (no borrowers)
    // Should be able to supply more ERC20 after already having supply ERC20
    function test_supply_more_after_supply() public {
        uint256 amount = 10 * 1e18;
        uint256 amountToApprove = 10 * 1e18 * 2;
        uint256 daiBalanceBefore = supplier1.balanceOf(dai);

        supplier1.approve(dai, address(positionsManager), amountToApprove);
        supplier1.supply(aDai, amount);
        uint256 normalizedIncome1 = lendingPool.getReserveNormalizedIncome(dai);
        supplier1.supply(aDai, amount);
        uint256 normalizedIncome2 = lendingPool.getReserveNormalizedIncome(dai);

        // Check ERC20 balance
        uint256 daiBalanceAfter = supplier1.balanceOf(dai);
        assertEq(daiBalanceAfter, daiBalanceBefore - amountToApprove);

        // Check supply balance
        uint256 expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(amount, normalizedIncome1);
        uint256 expectedSupplyBalanceOnPool2 = underlyingToScaledBalance(amount, normalizedIncome2);
        uint256 expectedSupplyBalanceOnPool = expectedSupplyBalanceOnPool1 +
            expectedSupplyBalanceOnPool2;
        assertEq(
            IAToken(aDai).scaledBalanceOf(address(positionsManager)),
            expectedSupplyBalanceOnPool
        );

        (, uint256 onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(onPool, expectedSupplyBalanceOnPool);
    }

    // Suppliers on Aave (no borrowers)
    // Several suppliers should be able to supply and have the correct balances
    function test_several_suppliers() public {
        uint256 amount = 10 * 1e18;
        uint256 expectedScaledBalance = 0;

        User[3] memory suppliers = [supplier1, supplier2, supplier3];
        for (uint256 i = 0; i < suppliers.length; i++) {
            User supplier = suppliers[i];

            uint256 daiBalanceBefore = supplier.balanceOf(dai);
            uint256 expectedDaiBalanceAfter = daiBalanceBefore - amount;
            supplier.approve(dai, address(positionsManager), amount);
            supplier.supply(aDai, amount);
            uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
            uint256 daiBalanceAfter = supplier.balanceOf(dai);
            uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(
                amount,
                normalizedIncome
            );

            // Check ERC20 balance
            assertEq(daiBalanceAfter, expectedDaiBalanceAfter);
            expectedScaledBalance += expectedSupplyBalanceOnPool;

            uint256 scaledBalance = IAToken(aDai).scaledBalanceOf(address(positionsManager));
            uint256 diff;
            if (scaledBalance > expectedScaledBalance) {
                diff = scaledBalance - expectedScaledBalance;
            } else {
                diff = expectedScaledBalance - scaledBalance;
            }

            assertEq(diff, 0);
            (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
                aDai,
                address(supplier)
            );
            assertEq(onPool, expectedSupplyBalanceOnPool);
            assertEq(inP2P, 0);
        }
    }

    // ====================================
    // = Borrowers on Aave (no suppliers) =
    // ====================================

    // Borrowers on Aave (no suppliers)
    // Should have correct balances at the beginning
    function test_correct_balances_at_begining() public {
        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(inP2P, 0);
        assertEq(onPool, 0);
    }

    // Borrowers on Aave (no suppliers)
    // Should revert when providing 0 as collateral
    function testFail_revert_when_providing_0_as_collateral() public {
        supplier1.supply(aDai, 0);
    }

    // Borrowers on Aave (no suppliers)
    // Should revert when borrow less than threshold
    function testFail_when_borrow_less_than_threshold() public {
        uint256 amount = to6Decimals(positionsManager.threshold(aDai) - 1);
        borrower1.approve(dai, address(positionsManager), amount);
        borrower1.borrow(aDai, amount);
    }

    // Borrowers on Aave (no suppliers)
    // Should be able to borrow on Aave after providing collateral up to max
    function test_borrow_on_aave_after_providing_collateral() public {
        uint256 amount = to6Decimals(100 ether);
        borrower1.approve(usdc, address(positionsManager), amount);
        borrower1.supply(aUsdc, amount);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        (, uint256 collateralBalanceInScaledBalance) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(borrower1)
        );
        uint256 collateralBalanceInUnderlying = scaledBalanceToUnderlying(
            collateralBalanceInScaledBalance,
            normalizedIncome
        );

        (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
            .getReserveConfigurationData(dai);
        uint256 usdcPrice = oracle.getAssetPrice(usdc);
        uint8 usdcDecimals = ERC20(usdc).decimals();
        uint256 daiPrice = oracle.getAssetPrice(dai);
        uint8 daiDecimals = ERC20(dai).decimals();
        uint256 maxToBorrow = (((((collateralBalanceInUnderlying * usdcPrice) / 10**usdcDecimals) *
            10**daiDecimals) / daiPrice) * liquidationThreshold) / PERCENT_BASE;
        uint256 daiBalanceBefore = borrower1.balanceOf(dai);

        // Borrow
        borrower1.borrow(aDai, maxToBorrow);
        uint256 daiBalanceAfter = borrower1.balanceOf(dai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);

        // Check borrower1 balances
        assertEq(daiBalanceAfter, daiBalanceBefore + maxToBorrow);
        (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
        uint256 borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
            onPool,
            normalizedVariableDebt
        );

        uint256 diff;
        if (borrowBalanceOnPoolInUnderlying > maxToBorrow) {
            diff =
                borrowBalanceOnPoolInUnderlying -
                underlyingToAdUnit(maxToBorrow, normalizedVariableDebt);
        } else {
            diff = maxToBorrow - borrowBalanceOnPoolInUnderlying;
        }

        assertEq(diff, 0);

        // Check Morpho balances
        assertEq(IERC20(dai).balanceOf(address(positionsManager)), 0);
        assertEq(IERC20(variableDebtDai).balanceOf(address(positionsManager)), maxToBorrow);
    }

    // Borrowers on Aave (no suppliers)
    // Should not be able to borrow more than max allowed given an amount of collateral
    function testFail_borrow_more_than_max_allowed() public {
        uint256 amount = to6Decimals(100 ether);
        borrower1.approve(usdc, address(positionsManager), amount);
        borrower1.supply(aUsdc, amount);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        (, uint256 collateralBalanceInScaledBalance) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(borrower1)
        );
        uint256 collateralBalanceInUnderlying = scaledBalanceToUnderlying(
            collateralBalanceInScaledBalance,
            normalizedIncome
        );
        (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
            .getReserveConfigurationData(dai);
        uint256 usdcPrice = oracle.getAssetPrice(usdc);
        uint8 usdcDecimals = ERC20(usdc).decimals();
        uint256 daiPrice = oracle.getAssetPrice(dai);
        uint8 daiDecimals = ERC20(dai).decimals();
        uint256 maxToBorrow = (((((collateralBalanceInUnderlying * usdcPrice) / 10**usdcDecimals) *
            10**daiDecimals) / daiPrice) * liquidationThreshold) / PERCENT_BASE;
        // WARNING: maxToBorrow seems to be not accurate
        uint256 moreThanMaxToBorrow = maxToBorrow + 10 ether;

        // TODO: fix dust issue
        // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
        borrower1.borrow(aDai, moreThanMaxToBorrow);
    }

    // Borrowers on Aave (no suppliers)
    // Several borrowers should be able to borrow and have the correct balances
    function test_several_borrowers_correct_balances() public {
        uint256 collateralAmount = to6Decimals(10 ether);
        uint256 borrowedAmount = 2 ether;
        uint256 expectedMorphoBorrowBalance = 0;
        uint256 previousNormalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);

        User[3] memory borrowers = [borrower1, borrower2, borrower3];
        for (uint256 i = 0; i < borrowers.length; i++) {
            User borrower = borrowers[i];

            borrower.approve(usdc, address(positionsManager), collateralAmount);
            borrower.supply(aUsdc, collateralAmount);
            uint256 daiBalanceBefore = borrower.balanceOf(dai);

            borrower.borrow(aDai, borrowedAmount);
            // We have one block delay from Aave
            uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
            expectedMorphoBorrowBalance =
                (expectedMorphoBorrowBalance * normalizedVariableDebt) /
                previousNormalizedVariableDebt +
                borrowedAmount;

            // All underlyings should have been sent to the borrower
            uint256 daiBalanceAfter = borrower.balanceOf(dai);
            assertEq(daiBalanceAfter, daiBalanceBefore + borrowedAmount);
            (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
            uint256 borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
                onPool,
                normalizedVariableDebt
            );
            uint256 diff;
            if (borrowBalanceOnPoolInUnderlying > borrowedAmount) {
                diff = borrowBalanceOnPoolInUnderlying - borrowedAmount;
            } else {
                diff = borrowedAmount - borrowBalanceOnPoolInUnderlying;
            }

            assertEq(diff, 0);
            // Update previous borrow index
            previousNormalizedVariableDebt = normalizedVariableDebt;
        }

        // Check Morpho balances
        assertEq(IERC20(dai).balanceOf(address(positionsManager)), 0);
        assertEq(
            IERC20(variableDebtDai).balanceOf(address(positionsManager)),
            expectedMorphoBorrowBalance
        );
    }

    // Borrowers on Aave (no suppliers)
    // Borrower should be able to repay less than what is on Aave
    function test_repay_less_than_on_aave() public {
        uint256 amount = to6Decimals(100 ether);
        borrower1.approve(usdc, address(positionsManager), amount);
        borrower1.supply(aUsdc, amount);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        (, uint256 collateralBalanceInScaledBalance) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(borrower1)
        );
        uint256 collateralBalanceInUnderlying = scaledBalanceToUnderlying(
            collateralBalanceInScaledBalance,
            normalizedIncome
        );
        (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
            .getReserveConfigurationData(dai);
        uint256 usdcPrice = oracle.getAssetPrice(usdc);
        uint8 usdcDecimals = ERC20(usdc).decimals();
        uint256 daiPrice = oracle.getAssetPrice(dai);
        uint8 daiDecimals = ERC20(dai).decimals();
        uint256 maxToBorrow = (((((collateralBalanceInUnderlying * usdcPrice) / 10**usdcDecimals) *
            10**daiDecimals) / daiPrice) * liquidationThreshold) / PERCENT_BASE;

        emit log_named_uint("maxToBorrow", maxToBorrow);
        uint256 daiBalanceBefore = borrower1.balanceOf(dai);
        borrower1.borrow(aDai, maxToBorrow);

        (, uint256 borrowBalanceOnPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        uint256 normalizeVariableDebt1 = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 borrowBalanceOnPoolInUnderlying = aDUnitToUnderlying(
            borrowBalanceOnPool,
            normalizeVariableDebt1
        );
        uint256 toRepay = borrowBalanceOnPoolInUnderlying / 2;
        borrower1.approve(dai, address(positionsManager), toRepay);
        borrower1.repay(aDai, toRepay);
        uint256 normalizeVariableDebt2 = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 daiBalanceAfter = borrower1.balanceOf(dai);

        uint256 expectedBalanceOnPool = borrowBalanceOnPool -
            underlyingToAdUnit(borrowBalanceOnPoolInUnderlying / 2, normalizeVariableDebt2);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
        assertEq(onPool, expectedBalanceOnPool);
        assertEq(daiBalanceAfter, daiBalanceBefore + maxToBorrow - toRepay);
    }

    // ===================================================
    // = P2P interactions between supplier and borrowers =
    // ===================================================

    // P2P interactions between supplier and borrowers
    // Supplier should withdraw her liquidity while not enough aToken in peer-to-peer contract
    function test_withdraw_liquidity_while_not_enough_in_p2p() public {
        /* TODO: Resolve STACK TOO DEEP */
        /*
        // Supplier supplies tokens
        uint256 supplyAmount = 10 ether;
        uint256 expectedDaiBalanceAfter = supplier1.balanceOf(dai) - supplyAmount;
        supplier1.approve(dai, address(positionsManager), supplyAmount);
        supplier1.supply(aDai, supplyAmount);

        // Check ERC20 balance
        assertEq(supplier1.balanceOf(dai), expectedDaiBalanceAfter);
        uint256 expectedSupplyBalanceOnPool1 = underlyingToScaledBalance(
            supplyAmount,
            lendingPool.getReserveNormalizedIncome(dai)
        );
        assertEq(
            IAToken(aDai).scaledBalanceOf(address(positionsManager)),
            expectedSupplyBalanceOnPool1
        );

        (uint256 inP2P, uint256 onPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );
        assertEq(onPool, expectedSupplyBalanceOnPool1);

        // Borrower provides collateral
        uint256 collateralAmount = to6Decimals(100 ether);
        borrower1.approve(usdc, address(positionsManager), collateralAmount);
        borrower1.supply(aUsdc, collateralAmount);

        // Borrowers borrows supplier1 amount
        borrower1.borrow(aDai, supplyAmount);

        // Check supplier1 balances
        uint256 p2pExchangeRate1 = marketsManager.p2pUnitExchangeRate(aDai);
        uint256 expectedSupplyBalanceOnPool2 = expectedSupplyBalanceOnPool1 -
            underlyingToScaledBalance(supplyAmount, lendingPool.getReserveNormalizedIncome(dai));
        uint256 expectedSupplyBalanceInP2P2 = underlyingToP2PUnit(supplyAmount, p2pExchangeRate1);
        (uint256 supplyBalanceInP2P2, uint256 supplyBalanceOnPool2) = positionsManager
            .supplyBalanceInOf(aDai, address(supplier1));

        assertEq(supplyBalanceOnPool2, expectedSupplyBalanceOnPool2);
        assertEq(supplyBalanceInP2P2, expectedSupplyBalanceInP2P2);

        // Check borrower1 balances
        uint256 expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
        (inP2P, onPool) = positionsManager.borrowBalanceInOf(aDai, address(borrower1));
        assertEq(onPool, 0);
        assertEq(inP2P, expectedBorrowBalanceInP2P1);

        // Compare remaining to withdraw and the aToken contract balance
        marketsManager.updateP2PUnitExchangeRate(aDai);
        uint256 p2pExchangeRate2 = marketsManager.p2pUnitExchangeRate(aDai);
        uint256 p2pExchangeRate3 = computeNewMorphoExchangeRate(
            p2pExchangeRate2,
            marketsManager.p2pSPY(aDai),
            1,
            0
        );

        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        uint256 normalizedIncome3 = lendingPool.getReserveNormalizedIncome(dai);
        uint256 supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(
            onPool,
            normalizedIncome3
        );
        uint256 amountToWithdraw = supplyBalanceOnPoolInUnderlying +
            p2pUnitToUnderlying(inP2P, p2pExchangeRate3);
        expectedDaiBalanceAfter = supplier1.balanceOf(dai) + amountToWithdraw;
        uint256 remainingToWithdraw = amountToWithdraw - supplyBalanceOnPoolInUnderlying;
        uint256 aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(
            IERC20(aDai).balanceOf(address(positionsManager)),
            normalizedIncome3
        );
        assertGt(remainingToWithdraw, aTokenContractBalanceInUnderlying);

        // Expected borrow balances
        uint256 expectedMorphoBorrowBalance = remainingToWithdraw +
            aTokenContractBalanceInUnderlying -
            supplyBalanceOnPoolInUnderlying;

        // Withdraw
        supplier1.withdraw(aDai, amountToWithdraw);
        uint256 expectedBorrowerBorrowBalanceOnPool = underlyingToAdUnit(
            expectedMorphoBorrowBalance,
            lendingPool.getReserveNormalizedVariableDebt(dai)
        );

        // Check borrow balance of Morpho
        assertEq(
            IERC20(variableDebtDai).balanceOf(address(positionsManager)),
            expectedMorphoBorrowBalance
        );

        // Check supplier1 underlying balance
        assertEq(supplier1.balanceOf(dai), expectedDaiBalanceAfter);

        // Check supply balances of supplier1
        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertEq(onPool, 0);
        assertEq(inP2P, 0);

        // Check borrow balances of borrower1
        (inP2P, onPool) = positionsManager.supplyBalanceInOf(aDai, address(borrower1));
        assertEq(onPool, expectedBorrowerBorrowBalanceOnPool);
        assertEq(inP2P, 0);
        */
    }

    // P2P interactions between supplier and borrowers
    // Supplier should withdraw her liquidity while enough aDaiToken in peer-to-peer contract
    function test_withdraw_liquidity_while_enough_adaitoken_in_p2p() public {
        /*
      const supplyAmount = utils.parseUnits('10');
      let supplier;

      for (const i in suppliers) {
        supplier = suppliers[i];
        const daiBalanceBefore = await daiToken.balanceOf(supplier.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(supplyAmount);
        await daiToken.connect(supplier).approve(positionsManagerForAave.address, supplyAmount);
        await positionsManagerForAave.connect(supplier).supply(aDai, supplyAmount);
        const daiBalanceAfter = await daiToken.balanceOf(supplier.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const normalizedIncome = await lendingPool.getReserveNormalizedIncome(dai);
        const expectedSupplyBalanceOnPool = underlyingToScaledBalance(supplyAmount, normalizedIncome);
        expect(
          removeDigitsBigNumber(
            4,
            (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier.getAddress())).onPool
          )
        ).to.equal(removeDigitsBigNumber(4, expectedSupplyBalanceOnPool));
      }

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);

      const previousSupplier1SupplyBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress())
      ).onPool;

      // Borrowers borrows supplier1 amount
      await positionsManagerForAave.connect(borrower1).borrow(aDai, supplyAmount);

      // Check supplier1 balances
      const p2pExchangeRate1 = await marketsManagerForAave.p2pUnitExchangeRate(aDai);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(dai);
      // Expected balances of supplier1
      const expectedSupplyBalanceOnPool2 = previousSupplier1SupplyBalanceOnPool.sub(
        underlyingToScaledBalance(supplyAmount, normalizedIncome2)
      );
      const expectedSupplyBalanceInP2P2 = underlyingToP2PUnit(supplyAmount, p2pExchangeRate1);
      const supplyBalanceOnPool2 = (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress()))
        .onPool;
      const supplyBalanceInP2P2 = (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress()))
        .inP2P;
      expect(removeDigitsBigNumber(2, supplyBalanceOnPool2)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceOnPool2));
      expect(removeDigitsBigNumber(2, supplyBalanceInP2P2)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceInP2P2));

      // Check borrower1 balances
      const expectedBorrowBalanceInP2P1 = expectedSupplyBalanceInP2P2;
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).onPool).to.equal(0);
      expect(
        removeDigitsBigNumber(
          2,
          (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(2, expectedBorrowBalanceInP2P1));

      // Compare remaining to withdraw and the aToken contract balance
      await marketsManagerForAave.connect(owner).updateP2PUnitExchangeRate(aDai);
      const p2pExchangeRate2 = await marketsManagerForAave.p2pUnitExchangeRate(aDai);
      const p2pExchangeRate3 = computeNewMorphoExchangeRate(
        p2pExchangeRate2,
        await marketsManagerForAave.p2pSPY(aDai),
        1,
        0
      );
      const daiBalanceBefore2 = await daiToken.balanceOf(supplier1.getAddress());
      const supplyBalanceOnPool3 = (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress()))
        .onPool;
      const supplyBalanceInP2P3 = (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress()))
        .inP2P;
      const normalizedIncome3 = await lendingPool.getReserveNormalizedIncome(dai);
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool3, normalizedIncome3);
      const amountToWithdraw = supplyBalanceOnPoolInUnderlying.add(p2pUnitToUnderlying(supplyBalanceInP2P3, p2pExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(supplyBalanceOnPoolInUnderlying);
      const aTokenContractBalanceInUnderlying = scaledBalanceToUnderlying(
        await aDaiToken.balanceOf(positionsManagerForAave.address),
        normalizedIncome3
      );
      expect(remainingToWithdraw).to.be.lt(aTokenContractBalanceInUnderlying);

      // supplier3 balances before the withdraw
      const supplier3SupplyBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(aDai, supplier3.getAddress())
      ).onPool;
      const supplier3SupplyBalanceInP2P = (
        await positionsManagerForAave.supplyBalanceInOf(aDai, supplier3.getAddress())
      ).inP2P;

      // supplier2 balances before the withdraw
      const supplier2SupplyBalanceOnPool = (
        await positionsManagerForAave.supplyBalanceInOf(aDai, supplier2.getAddress())
      ).onPool;
      const supplier2SupplyBalanceInP2P = (
        await positionsManagerForAave.supplyBalanceInOf(aDai, supplier2.getAddress())
      ).inP2P;

      // borrower1 balances before the withdraw
      const borrower1BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())
      ).onPool;
      const borrower1BorrowBalanceInP2P = (
        await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())
      ).inP2P;

      // Withdraw
      await positionsManagerForAave.connect(supplier1).withdraw(aDai, amountToWithdraw);
      const normalizedIncome4 = await lendingPool.getReserveNormalizedIncome(dai);
      const borrowBalance = await variableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(supplier1.getAddress());

      const supplier2SupplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplier2SupplyBalanceOnPool, normalizedIncome4);
      const amountToMove = bigNumberMin(supplier2SupplyBalanceOnPoolInUnderlying, remainingToWithdraw);
      const p2pExchangeRate4 = await marketsManagerForAave.p2pUnitExchangeRate(aDai);
      const expectedSupplier2SupplyBalanceOnPool = supplier2SupplyBalanceOnPool.sub(
        underlyingToScaledBalance(amountToMove, normalizedIncome4)
      );
      const expectedSupplier2SupplyBalanceInP2P = supplier2SupplyBalanceInP2P.add(underlyingToP2PUnit(amountToMove, p2pExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check supplier1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check supply balances of supplier1
      expect(
        removeDigitsBigNumber(
          1,
          (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress())).onPool
        )
      ).to.equal(0);
      expect(
        removeDigitsBigNumber(
          5,
          (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress())).inP2P
        )
      ).to.equal(0);

      // Check supply balances of supplier2: supplier2 should have replaced supplier1
      expect(
        removeDigitsBigNumber(
          4,
          (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier2.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(4, expectedSupplier2SupplyBalanceOnPool));
      expect(
        removeDigitsBigNumber(
          7,
          (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier2.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(7, expectedSupplier2SupplyBalanceInP2P));

      // Check supply balances of supplier3: supplier3 balances should not move
      expect((await positionsManagerForAave.supplyBalanceInOf(aDai, supplier3.getAddress())).onPool).to.equal(
        supplier3SupplyBalanceOnPool
      );
      expect((await positionsManagerForAave.supplyBalanceInOf(aDai, supplier3.getAddress())).inP2P).to.equal(
        supplier3SupplyBalanceInP2P
      );

      // Check borrow balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).onPool).to.equal(
        borrower1BorrowBalanceOnPool
      );
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).inP2P).to.equal(
        borrower1BorrowBalanceInP2P
      );
      */
    }

    // P2P interactions between supplier and borrowers
    // Borrower in peer-to-peer only, should be able to repay all borrow amount
    function test_borrower_in_p2p_only_repay_all_borrow() public {
        /*
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(aDai, supplyAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.div(2);

      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).borrow(aDai, toBorrow);

      const borrowerBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress()))
        .inP2P;
      const p2pSPY = await marketsManagerForAave.p2pSPY(aDai);
      await marketsManagerForAave.updateP2PUnitExchangeRate(aDai);
      const p2pUnitExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(aDai);
      const p2pExchangeRate: BigNumber = computeNewMorphoExchangeRate(p2pUnitExchangeRate, p2pSPY, AVERAGE_BLOCK_TIME, 0);
      const toRepay = p2pUnitToUnderlying(borrowerBalanceInP2P, p2pExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoScaledBalance = await aDaiToken.scaledBalanceOf(positionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);
      await positionsManagerForAave.connect(borrower1).repay(aDai, toRepay);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(dai);
      const expectedMorphoScaledBalance = previousMorphoScaledBalance.add(underlyingToScaledBalance(toRepay, normalizedIncome));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).onPool).to.equal(0);
      // Commented here due to the pow function issue
      // expect(removeDigitsBigNumber(1, (await positionsManagerForAave.borrowBalanceInOf(borrower1.getAddress())).inP2P)).to.equal(0);

      // Check Morpho balances
      expect(removeDigitsBigNumber(3, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(3, expectedMorphoScaledBalance)
      );
      expect(await variableDebtDaiToken.balanceOf(positionsManagerForAave.address)).to.equal(0);
      */
    }

    // P2P interactions between supplier and borrowers
    // Borrower in peer-to-peer and on Aave, should be able to repay all borrow amount
    function test_borrower_in_p2p_and_aave_repay_all_borrow() public {
        /*
      // Supplier supplys tokens
      const supplyAmount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('100000000');
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(aDai, supplyAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = supplyAmount.mul(2);
      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress()))
        .onPool;
      await positionsManagerForAave.connect(borrower1).borrow(aDai, toBorrow);

      const normalizedIncome1 = await lendingPool.getReserveNormalizedIncome(dai);
      const expectedMorphoBorrowBalance1 = toBorrow.sub(scaledBalanceToUnderlying(supplyBalanceOnPool, normalizedIncome1));
      const morphoBorrowBalanceBefore1 = await variableDebtDaiToken.balanceOf(positionsManagerForAave.address);
      expect(removeDigitsBigNumber(6, morphoBorrowBalanceBefore1)).to.equal(removeDigitsBigNumber(6, expectedMorphoBorrowBalance1));
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, amountToApprove);

      const borrowerBalanceInP2P = (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress()))
        .inP2P;
      const p2pSPY = await marketsManagerForAave.p2pSPY(aDai);
      const p2pUnitExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(aDai);
      const p2pExchangeRate = computeNewMorphoExchangeRate(p2pUnitExchangeRate, p2pSPY, AVERAGE_BLOCK_TIME * 2, 0);
      const borrowerBalanceInP2PInUnderlying = p2pUnitToUnderlying(borrowerBalanceInP2P, p2pExchangeRate);

      // Compute how much to repay
      const normalizeVariableDebt1 = await lendingPool.getReserveNormalizedVariableDebt(dai);
      const borrowerBalanceOnPool = (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress()))
        .onPool;
      const toRepay = aDUnitToUnderlying(borrowerBalanceOnPool, normalizeVariableDebt1).add(borrowerBalanceInP2PInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoScaledBalance = await aDaiToken.scaledBalanceOf(positionsManagerForAave.address);

      // Repay
      await daiToken.connect(borrower1).approve(positionsManagerForAave.address, toRepay);
      await positionsManagerForAave.connect(borrower1).repay(aDai, toRepay);
      const normalizedIncome2 = await lendingPool.getReserveNormalizedIncome(dai);
      const expectedMorphoScaledBalance = previousMorphoScaledBalance.add(
        underlyingToScaledBalance(borrowerBalanceInP2PInUnderlying, normalizedIncome2)
      );

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())
      ).onPool;
      expect(removeDigitsBigNumber(2, borrower1BorrowBalanceOnPool)).to.equal(0);
      // WARNING: Commented here due to the pow function issue
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).inP2P).to.be.lt(
        1000000000000
      );

      // Check Morpho balances
      expect(removeDigitsBigNumber(13, await aDaiToken.scaledBalanceOf(positionsManagerForAave.address))).to.equal(
        removeDigitsBigNumber(13, expectedMorphoScaledBalance)
      );
      // Issue here: we cannot access the most updated borrow balance as it's updated during the repayBorrow on Aave.
      // const expectedMorphoBorrowBalance2 = morphoBorrowBalanceBefore2.sub(borrowerBalanceOnPool.mul(normalizeVariableDebt2).div(WAD));
      // expect(removeDigitsBigNumber(3, await aToken.callStatic.borrowBalanceStored(positionsManagerForAave.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowBalance2));
      */
    }

    // P2P interactions between supplier and borrowers
    // Supplier should be connected to borrowers on pool when supplying
    function test_supplier_connected_to_borrowers_on_pool_when_supplying() public {
        /*
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const supplyAmount = utils.parseUnits('100');
      const borrowAmount = utils.parseUnits('30');

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower1).borrow(aDai, borrowAmount);
      const borrower1BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())
      ).onPool;

      // borrower2 borrows
      await usdcToken.connect(borrower2).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower2).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower2).borrow(aDai, borrowAmount);
      const borrower2BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(aDai, borrower2.getAddress())
      ).onPool;

      // borrower3 borrows
      await usdcToken.connect(borrower3).approve(positionsManagerForAave.address, collateralAmount);
      await positionsManagerForAave.connect(borrower3).supply(config.tokens.aUsdc.address, collateralAmount);
      await positionsManagerForAave.connect(borrower3).borrow(aDai, borrowAmount);
      const borrower3BorrowBalanceOnPool = (
        await positionsManagerForAave.borrowBalanceInOf(aDai, borrower3.getAddress())
      ).onPool;

      // supplier1 supply
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, supplyAmount);
      await positionsManagerForAave.connect(supplier1).supply(aDai, supplyAmount);
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(dai);
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(dai);
      const p2pUnitExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(aDai);

      // Check balances
      const supplyBalanceInP2P = (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress()))
        .inP2P;
      const supplyBalanceOnPool = (await positionsManagerForAave.supplyBalanceInOf(aDai, supplier1.getAddress()))
        .onPool;
      const underlyingMatched = aDUnitToUnderlying(
        borrower1BorrowBalanceOnPool.add(borrower2BorrowBalanceOnPool).add(borrower3BorrowBalanceOnPool),
        normalizedVariableDebt
      );
      const expectedSupplyBalanceInP2P = underlyingToAdUnit(underlyingMatched, p2pUnitExchangeRate);
      const expectedSupplyBalanceOnPool = underlyingToScaledBalance(supplyAmount.sub(underlyingMatched), normalizedIncome);
      expect(removeDigitsBigNumber(2, supplyBalanceInP2P)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceInP2P));
      expect(removeDigitsBigNumber(2, supplyBalanceOnPool)).to.equal(removeDigitsBigNumber(2, expectedSupplyBalanceOnPool));
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower2.getAddress())).onPool).to.be.lte(1);
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower3.getAddress())).onPool).to.be.lte(1);
      */
    }

    // P2P interactions between supplier and borrowers
    // Borrower should be connected to suppliers on pool in peer-to-peer when borrowing
    function test_borrower_connected_to_suppliers_on_pool_in_p2p_when_borrowing() public {
        uint256 collateralAmount = to6Decimals(140 ether);
        uint256 supplyAmount = 30 ether;
        uint256 borrowAmount = 100 ether;

        // supplier1 supplies
        supplier1.approve(dai, address(positionsManager), supplyAmount);
        supplier1.supply(aDai, supplyAmount);
        (, uint256 supplier1BorrowBalanceOnPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        // supplier2 supplies
        supplier2.approve(dai, address(positionsManager), supplyAmount);
        supplier2.supply(aDai, supplyAmount);
        (, uint256 supplier2BorrowBalanceOnPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier2)
        );

        // supplier3 supplies
        supplier3.approve(dai, address(positionsManager), supplyAmount);
        supplier3.supply(aDai, supplyAmount);
        (, uint256 supplier3BorrowBalanceOnPool) = positionsManager.supplyBalanceInOf(
            aDai,
            address(supplier3)
        );

        // borrower1 borrows
        borrower1.approve(usdc, address(positionsManager), collateralAmount);
        borrower1.supply(aUsdc, collateralAmount);
        borrower1.borrow(aDai, borrowAmount);
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(dai);
        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(dai);
        uint256 p2pUnitExchangeRate = marketsManager.p2pUnitExchangeRate(aDai);

        // Check balances
        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );
        uint256 underlyingMatched = scaledBalanceToUnderlying(
            supplier1BorrowBalanceOnPool +
                supplier2BorrowBalanceOnPool +
                supplier3BorrowBalanceOnPool,
            normalizedIncome
        );

        uint256 expectedBorrowBalanceInP2P = underlyingToP2PUnit(
            underlyingMatched,
            p2pUnitExchangeRate
        );
        uint256 expectedBorrowBalanceOnPool = underlyingToAdUnit(
            borrowAmount - underlyingMatched,
            normalizedVariableDebt
        );

        assertEq(inP2P, expectedBorrowBalanceInP2P);
        assertEq(onPool, expectedBorrowBalanceOnPool);

        (, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier1));
        assertLe(onPool, 1);
        (, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier2));
        assertLe(onPool, 1);
        (, onPool) = positionsManager.supplyBalanceInOf(aDai, address(supplier3));
        assertLe(onPool, 1);
    }

    // ====================
    // = Test liquidation =
    // ====================

    // Test liquidation
    // Borrower should be liquidated while supply (collateral) is only on Aave
    function test_borrower_liquidated_while_supply_on_aave() public {
        /*
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('contracts/aave/test/SimplePriceOracle.sol:SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await lendingPoolAddressesProvider.owner();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);

      // Deposit
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);
      const collateralBalanceInScaledBalance = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).onPool;
      const normalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const collateralBalanceInUnderlying = scaledBalanceToUnderlying(collateralBalanceInScaledBalance, normalizedIncome);
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(dai);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.usdc.address);
      const usdcDecimals = await usdcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(dai);
      const daiDecimals = await daiToken.decimals();
      const maxToBorrow = collateralBalanceInUnderlying
        .mul(usdcPrice)
        .div(BigNumber.from(10).pow(usdcDecimals))
        .mul(BigNumber.from(10).pow(daiDecimals))
        .div(daiPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);

      // Borrow DAI
      await positionsManagerForAave.connect(borrower1).borrow(aDai, maxToBorrow);
      const collateralBalanceBefore = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress()))
        .onPool;
      const borrowBalanceBefore = (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress()))
        .onPool;

      // Set price oracle
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(priceOracle.address);
      priceOracle.setDirectPrice(dai, BigNumber.from('1070182920000000000'));
      priceOracle.setDirectPrice(config.tokens.usdc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.wbtc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.usdt.address, WAD);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate
      const toRepay = maxToBorrow.div(2);
      await daiToken.connect(liquidator).approve(positionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await positionsManagerForAave
        .connect(liquidator)
        .liquidate(aDai, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const normalizedVariableDebt = await lendingPool.getReserveNormalizedVariableDebt(dai);
      const cUsdNormalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const { liquidationBonus } = await protocolDataProvider.getReserveConfigurationData(config.tokens.usdc.address);
      const collateralAssetPrice = await priceOracle.getAssetPrice(config.tokens.usdc.address);
      const borrowedAssetPrice = await priceOracle.getAssetPrice(dai);
      const amountToSeize = toRepay
        .mul(borrowedAssetPrice)
        .div(BigNumber.from(10).pow(daiDecimals))
        .mul(BigNumber.from(10).pow(usdcDecimals))
        .div(collateralAssetPrice)
        .mul(liquidationBonus)
        .div(10000);
      const expectedCollateralBalanceAfter = collateralBalanceBefore.sub(underlyingToScaledBalance(amountToSeize, cUsdNormalizedIncome));
      const expectedBorrowBalanceAfter = borrowBalanceBefore.sub(underlyingToAdUnit(toRepay, normalizedVariableDebt));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check balances
      expect(
        removeDigitsBigNumber(
          6,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(6, expectedCollateralBalanceAfter));
      expect(
        removeDigitsBigNumber(
          2,
          (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).onPool
        )
      ).to.equal(removeDigitsBigNumber(2, expectedBorrowBalanceAfter));
      expect(removeDigitsBigNumber(2, usdcBalanceAfter)).to.equal(removeDigitsBigNumber(2, expectedUsdcBalanceAfter));
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      */
    }

    // Test liquidation
    // Borrower should be liquidated while supply (collateral) is on Aave and in peer-to-peer
    function test_borrower_liquidated_while_supply_on_aave_and_p2p() public {
        /*
      // Deploy custom price oracle
      const PriceOracle = await ethers.getContractFactory('contracts/aave/test/SimplePriceOracle.sol:SimplePriceOracle');
      priceOracle = await PriceOracle.deploy();
      await priceOracle.deployed();

      // Install admin user
      const adminAddress = await lendingPoolAddressesProvider.owner();
      await hre.network.provider.send('hardhat_impersonateAccount', [adminAddress]);
      await hre.network.provider.send('hardhat_setBalance', [adminAddress, ethers.utils.parseEther('10').toHexString()]);
      const admin = await ethers.getSigner(adminAddress);
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(oracle.address);

      // supplier1 supplies DAI
      await daiToken.connect(supplier1).approve(positionsManagerForAave.address, utils.parseUnits('200'));
      await positionsManagerForAave.connect(supplier1).supply(aDai, utils.parseUnits('200'));

      // borrower1 supplies USDC as supply (collateral)
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(positionsManagerForAave.address, amount);
      await positionsManagerForAave.connect(borrower1).supply(config.tokens.aUsdc.address, amount);

      // borrower2 borrows part of supply of borrower1 -> borrower1 has supply in peer-to-peer and on Aave
      const toBorrow = amount;
      const toSupply = BigNumber.from(10).pow(8);
      await wbtcToken.connect(borrower2).approve(positionsManagerForAave.address, toSupply);
      await positionsManagerForAave.connect(borrower2).supply(config.tokens.aWbtc.address, toSupply);
      await positionsManagerForAave.connect(borrower2).borrow(config.tokens.aUsdc.address, toBorrow);

      // borrower1 borrows DAI
      const usdcNormalizedIncome1 = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const p2pUsdcExchangeRate1 = await marketsManagerForAave.p2pUnitExchangeRate(config.tokens.aUsdc.address);
      const supplyBalanceOnPool1 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress()))
        .onPool;
      const supplyBalanceInP2P1 = (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress()))
        .inP2P;
      const supplyBalanceOnPoolInUnderlying = scaledBalanceToUnderlying(supplyBalanceOnPool1, usdcNormalizedIncome1);
      const supplyBalanceMorphoInUnderlying = p2pUnitToUnderlying(supplyBalanceInP2P1, p2pUsdcExchangeRate1);
      const supplyBalanceInUnderlying = supplyBalanceOnPoolInUnderlying.add(supplyBalanceMorphoInUnderlying);
      const { liquidationThreshold } = await protocolDataProvider.getReserveConfigurationData(dai);
      const usdcPrice = await oracle.getAssetPrice(config.tokens.usdc.address);
      const usdcDecimals = await usdcToken.decimals();
      const daiPrice = await oracle.getAssetPrice(dai);
      const daiDecimals = await daiToken.decimals();
      const maxToBorrow = supplyBalanceInUnderlying
        .mul(usdcPrice)
        .div(BigNumber.from(10).pow(usdcDecimals))
        .mul(BigNumber.from(10).pow(daiDecimals))
        .div(daiPrice)
        .mul(liquidationThreshold)
        .div(PERCENT_BASE);
      await positionsManagerForAave.connect(borrower1).borrow(aDai, maxToBorrow);
      const collateralBalanceOnPoolBefore = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).onPool;
      const collateralBalanceInP2PBefore = (
        await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())
      ).inP2P;
      const borrowBalanceInP2PBefore = (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress()))
        .inP2P;

      // Set price oracle
      await lendingPoolAddressesProvider.connect(admin).setPriceOracle(priceOracle.address);
      priceOracle.setDirectPrice(dai, BigNumber.from('1070182920000000000'));
      priceOracle.setDirectPrice(config.tokens.usdc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.wbtc.address, WAD);
      priceOracle.setDirectPrice(config.tokens.usdt.address, WAD);

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // liquidator liquidates borrower1's position
      const toRepay = maxToBorrow.mul(LIQUIDATION_CLOSE_FACTOR_PERCENT).div(10000);
      await daiToken.connect(liquidator).approve(positionsManagerForAave.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await positionsManagerForAave
        .connect(liquidator)
        .liquidate(aDai, config.tokens.aUsdc.address, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const p2pDaiExchangeRate = await marketsManagerForAave.p2pUnitExchangeRate(aDai);
      const usdcNormalizedIncome = await lendingPool.getReserveNormalizedIncome(config.tokens.usdc.address);
      const { liquidationBonus } = await protocolDataProvider.getReserveConfigurationData(config.tokens.usdc.address);
      const collateralAssetPrice = await priceOracle.getAssetPrice(config.tokens.usdc.address);
      const borrowedAssetPrice = await priceOracle.getAssetPrice(dai);
      const amountToSeize = toRepay
        .mul(borrowedAssetPrice)
        .mul(BigNumber.from(10).pow(usdcDecimals))
        .div(BigNumber.from(10).pow(daiDecimals))
        .div(collateralAssetPrice)
        .mul(liquidationBonus)
        .div(PERCENT_BASE);
      const expectedCollateralBalanceInP2PAfter = collateralBalanceInP2PBefore.sub(
        amountToSeize.sub(scaledBalanceToUnderlying(collateralBalanceOnPoolBefore, usdcNormalizedIncome))
      );
      const expectedBorrowBalanceInP2PAfter = borrowBalanceInP2PBefore.sub(underlyingToP2PUnit(toRepay, p2pDaiExchangeRate));
      const expectedUsdcBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check liquidatee balances
      expect((await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).onPool).to.equal(0);
      expect(
        removeDigitsBigNumber(
          2,
          (await positionsManagerForAave.supplyBalanceInOf(config.tokens.aUsdc.address, borrower1.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(2, expectedCollateralBalanceInP2PAfter));
      expect((await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).onPool).to.equal(0);
      expect(
        removeDigitsBigNumber(
          2,
          (await positionsManagerForAave.borrowBalanceInOf(aDai, borrower1.getAddress())).inP2P
        )
      ).to.equal(removeDigitsBigNumber(2, expectedBorrowBalanceInP2PAfter));

      // Check liquidator balances
      let diff;
      if (usdcBalanceAfter.gt(expectedUsdcBalanceAfter)) diff = usdcBalanceAfter.sub(expectedUsdcBalanceAfter);
      else diff = expectedUsdcBalanceAfter.sub(usdcBalanceAfter);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      */
    }

    // =============
    // = Cap value =
    // =============

    // Cap Value
    // Should be possible to supply up to cap value
    function supply_up_to_cap_value_prepare() public {
        marketsManager.updateCapValue(aDai, 2 ether);

        supplier1.approve(dai, address(positionsManager), 3 ether);
    }

    function test_supply_up_to_cap_value_1() public {
        supply_up_to_cap_value_prepare();

        supplier1.supply(aDai, 2 ether);
    }

    function testFail_supply_up_to_cap_value_2() public {
        supply_up_to_cap_value_prepare();

        supplier1.supply(aDai, 100 ether);
    }

    function testFail_supply_up_to_cap_value_3() public {
        supply_up_to_cap_value_prepare();

        supplier1.supply(aDai, 1);
    }

    // =========================
    // = Test claiming rewards =
    // =========================

    // Test claiming rewards
    // Anyone should be able to claim rewards on several markets
    function test_claim_rewards_on_several_markets() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = to6Decimals(50 ether);

        address owner = marketsManager.owner();
        uint256 rewardTokenBalanceBefore = IERC20(wmatic).balanceOf(owner);
        supplier1.approve(dai, address(positionsManager), toSupply);
        supplier1.supply(aDai, toSupply);
        supplier1.borrow(aUsdc, toBorrow);

        // Mine 1000 blocks
        hevm.roll(block.number + 1000);
        hevm.warp(block.timestamp + 10000);

        address[] memory tokens = new address[](1);
        tokens[0] = variableDebtUsdc;
        supplier1.claimRewards(tokens);
        uint256 rewardTokenBalanceAfter1 = IERC20(wmatic).balanceOf(owner);
        assertGt(rewardTokenBalanceAfter1, rewardTokenBalanceBefore);

        tokens[0] = aDai;
        borrower1.claimRewards(tokens);
        uint256 rewardTokenBalanceAfter2 = IERC20(wmatic).balanceOf(owner);
        assertGt(rewardTokenBalanceAfter2, rewardTokenBalanceAfter1);
    }

    // ================
    // = Test attacks =
    // ================

    // Test attacks
    // Should not be possible to withdraw amount if the position turns to be under-collateralized
    function testFail_withdraw_amount_position_under_collateralized() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = to6Decimals(50 ether);

        // supplier1 deposits collateral
        supplier1.approve(dai, address(positionsManager), toSupply);
        supplier1.supply(aDai, toSupply);

        // supplier2 deposits collateral
        supplier2.approve(dai, address(positionsManager), toSupply);
        supplier2.supply(aDai, toSupply);

        // supplier1 tries to withdraw more than allowed
        supplier1.borrow(aUsdc, toBorrow);
        supplier1.withdraw(aDai, toSupply);
    }

    // Test attacks
    // Should be possible to withdraw amount while an attacker sends aToken to trick Morpho contract
    function test_withdraw_amount_while_attacker_send_atoken_to_morpho() public {
        uint256 toSupply = 100 ether;
        uint256 toSupplyCollateral = to6Decimals(200 ether);
        uint256 toBorrow = toSupply;

        // attacker sends aToken to positionsManager contract
        attacker.approve(dai, address(lendingPool), toSupply);
        attacker.deposit(dai, toSupply, address(attacker), 0);
        attacker.transfer(dai, address(positionsManager), toSupply);

        // supplier1 deposits collateral
        supplier1.approve(dai, address(positionsManager), toSupply);
        supplier1.supply(aDai, toSupply);

        // borrower1 deposits collateral
        borrower1.approve(usdc, address(positionsManager), toSupplyCollateral);
        borrower1.supply(aUsdc, toSupplyCollateral);

        // supplier1 tries to withdraw
        borrower1.borrow(aDai, toBorrow);
        supplier1.withdraw(aDai, toSupply);
    }
}
