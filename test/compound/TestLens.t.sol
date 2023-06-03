// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
    using CompoundMath for uint256;

    struct UserBalanceStates {
        uint256 collateralUsd;
        uint256 debtUsd;
        uint256 maxDebtUsd;
        uint256 liquidationUsd;
    }

    struct UserBalance {
        uint256 onPool;
        uint256 inP2P;
        uint256 totalBalance;
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            true,
            oracle
        );

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        assertEq(assetData.collateralFactor, collateralFactor);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.collateralUsd, 0);
        assertEq(assetData.maxDebtUsd, 0);
        assertEq(assetData.debtUsd, 0);
    }

    function testUserLiquidityDataForAssetWithSupply() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            true,
            oracle
        );

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        uint256 collateralValue = getBalanceOnCompound(amount, ICToken(cDai).exchangeRateStored())
        .mul(underlyingPrice);
        uint256 maxDebtValue = collateralValue.mul(collateralFactor);

        assertEq(assetData.collateralFactor, collateralFactor, "collateralFactor");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.collateralUsd, collateralValue, "collateralValue");
        assertEq(assetData.maxDebtUsd, maxDebtValue, "maxDebtValue");
        assertEq(assetData.debtUsd, 0, "debtValue");
    }

    struct Indexes {
        uint256 index1;
        uint256 index2;
    }

    function testUserLiquidityDataForAssetWithSupplyAndBorrow() public {
        Indexes memory indexes;
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 2;

        borrower1.approve(dai, type(uint256).max);
        indexes.index1 = ICToken(cDai).exchangeRateCurrent();
        borrower1.supply(cDai, amount);
        borrower1.borrow(cDai, toBorrow);

        indexes.index2 = ICToken(cDai).exchangeRateCurrent();

        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            true,
            oracle
        );

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        uint256 total;

        // To update p2p indexes on Morpho (they can change inside of a block because the poolSupplyIndex can change due to rounding errors).
        borrower1.supply(cDai, 1);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
        {
            uint256 onPool = amount.div(indexes.index1);
            uint256 matchedInP2P = toBorrow.div(morpho.p2pSupplyIndex(cDai));
            uint256 onPoolAfter = onPool - toBorrow.div(indexes.index2);
            total = onPoolAfter.mul(indexes.index2) + matchedInP2P.mul(morpho.p2pSupplyIndex(cDai));
        }

        uint256 collateralValue = total.mul(underlyingPrice);
        uint256 maxDebtValue = collateralValue.mul(collateralFactor);
        // Divide and multiply to take into account rounding errors.
        uint256 debtValue = toBorrow.div(p2pBorrowIndex).mul(p2pBorrowIndex).mul(underlyingPrice);

        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.collateralUsd, collateralValue, "collateralValue");
        assertEq(assetData.maxDebtUsd, maxDebtValue, "maxDebtValue");
        assertEq(assetData.debtUsd, debtValue, "debtValue");
    }

    function testUserLiquidityDataForAssetWithSupplyAndBorrowWithMultipleAssets() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        Types.AssetLiquidityData memory assetDataCDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            true,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            true,
            oracle
        );

        // Avoid stack too deep error.
        Types.AssetLiquidityData memory expectedDataCUsdc;
        expectedDataCUsdc.underlyingPrice = oracle.getUnderlyingPrice(cUsdc);

        expectedDataCUsdc.debtUsd = getBalanceOnCompound(toBorrow, ICToken(cUsdc).borrowIndex())
        .mul(expectedDataCUsdc.underlyingPrice);

        assertEq(
            assetDataCUsdc.underlyingPrice,
            expectedDataCUsdc.underlyingPrice,
            "underlyingPriceUsdc"
        );
        assertEq(assetDataCUsdc.collateralUsd, 0, "collateralValue");
        assertEq(assetDataCUsdc.maxDebtUsd, 0, "maxDebtValue");
        assertEq(assetDataCUsdc.debtUsd, expectedDataCUsdc.debtUsd, "debtValueUsdc");

        // Avoid stack too deep error.
        Types.AssetLiquidityData memory expectedDataCDai;

        (, expectedDataCDai.collateralFactor, ) = comptroller.markets(cDai);

        expectedDataCDai.underlyingPrice = oracle.getUnderlyingPrice(cDai);
        expectedDataCDai.collateralUsd = getBalanceOnCompound(
            amount,
            ICToken(cDai).exchangeRateStored()
        ).mul(expectedDataCDai.underlyingPrice);
        expectedDataCDai.maxDebtUsd = expectedDataCDai.collateralUsd.mul(
            expectedDataCDai.collateralFactor
        );

        assertEq(
            assetDataCDai.collateralFactor,
            expectedDataCDai.collateralFactor,
            "collateralFactor"
        );
        assertEq(
            assetDataCDai.underlyingPrice,
            expectedDataCDai.underlyingPrice,
            "underlyingPriceDai"
        );

        assertEq(assetDataCDai.collateralUsd, expectedDataCDai.collateralUsd, "collateralValueDai");
        assertEq(assetDataCDai.maxDebtUsd, expectedDataCDai.maxDebtUsd, "maxDebtValueDai");
        assertEq(assetDataCDai.debtUsd, 0, "debtValueDai");
    }

    function testMaxCapacitiesWithNothing() public {
        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        assertEq(withdrawable, 0);
        assertEq(borrowable, 0);
    }

    function testMaxCapacitiesWithSupply() public {
        uint256 amount = to6Decimals(10000 ether);

        borrower1.approve(usdc, amount);
        borrower1.supply(cUsdc, amount);

        Types.AssetLiquidityData memory assetDataCUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            true,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            true,
            oracle
        );

        uint256 expectedBorrowableUsdc = assetDataCUsdc.maxDebtUsd.div(
            assetDataCUsdc.underlyingPrice
        );
        uint256 expectedBorrowableDai = assetDataCUsdc.maxDebtUsd.div(
            assetDataCDai.underlyingPrice
        );

        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdc
        );

        assertApproxEqAbs(
            withdrawable,
            getBalanceOnCompound(amount, ICToken(cUsdc).exchangeRateStored()),
            1,
            "withdrawable USDC"
        );
        assertEq(borrowable, expectedBorrowableUsdc, "borrowable USDC");

        (withdrawable, borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
    }

    function testMaxCapacitiesWithSupplyAndBorrow() public {
        uint256 amount = 100 ether;

        borrower1.approve(bat, amount);
        borrower1.supply(cBat, amount);

        (uint256 withdrawableBatBefore, uint256 borrowableBatBefore) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), cBat);
        (uint256 withdrawableDaiBefore, uint256 borrowableDaiBefore) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        borrower1.borrow(cDai, borrowableDaiBefore / 2);

        (uint256 withdrawableBatAfter, uint256 borrowableBatAfter) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), cBat);
        (uint256 withdrawableDaiAfter, uint256 borrowableDaiAfter) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        (, uint256 batCollateralFactor, ) = comptroller.markets(cBat);

        assertApproxEqAbs(withdrawableBatBefore, amount, 1e9, "cannot withdraw all BAT");
        assertApproxEqAbs(
            borrowableBatBefore,
            amount.mul(batCollateralFactor),
            1e8,
            "cannot borrow all BAT"
        );
        assertEq(withdrawableDaiBefore, 0, "can withdraw DAI not supplied");
        assertApproxEqAbs(
            borrowableDaiBefore,
            amount.mul(batCollateralFactor).mul(
                oracle.getUnderlyingPrice(cBat).div(oracle.getUnderlyingPrice(cDai))
            ),
            1e8,
            "cannot borrow all DAI"
        );
        assertApproxEqAbs(
            borrowableBatAfter,
            borrowableBatBefore / 2,
            10,
            "cannot borrow half BAT"
        );
        assertEq(withdrawableDaiAfter, 0, "unexpected withdrawable DAI");
        assertApproxEqAbs(
            borrowableDaiAfter,
            borrowableDaiBefore / 2,
            10,
            "cannot borrow half DAI"
        );

        vm.expectRevert(PositionsManager.UnauthorisedWithdraw.selector);
        borrower1.withdraw(cBat, withdrawableBatAfter + 1e8);
    }

    function testUserBalanceWithoutMatching() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        UserBalance memory userSupplyBalance;

        (userSupplyBalance.onPool, userSupplyBalance.inP2P, userSupplyBalance.totalBalance) = lens
        .getCurrentSupplyBalanceInOf(cDai, address(borrower1));

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.mul(morpho.p2pSupplyIndex(cDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.mul(
            ICToken(cDai).exchangeRateCurrent()
        );
        uint256 expectedTotalSupplyBalance = expectedSupplyBalanceInP2P +
            expectedSupplyBalanceOnPool;

        assertEq(userSupplyBalance.onPool, expectedSupplyBalanceOnPool, "On pool supply balance");
        assertEq(userSupplyBalance.inP2P, expectedSupplyBalanceInP2P, "P2P supply balance");
        assertEq(
            userSupplyBalance.totalBalance,
            expectedTotalSupplyBalance,
            "Total supply balance"
        );

        UserBalance memory userBorrowBalance;

        (userBorrowBalance.onPool, userBorrowBalance.inP2P, userBorrowBalance.totalBalance) = lens
        .getCurrentBorrowBalanceInOf(cUsdc, address(borrower1));

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.mul(morpho.p2pBorrowIndex(cUsdc));
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.mul(ICToken(cUsdc).borrowIndex());
        uint256 expectedTotalBorrowBalance = expectedBorrowBalanceInP2P +
            expectedBorrowBalanceOnPool;

        assertEq(userBorrowBalance.onPool, expectedBorrowBalanceOnPool, "On pool borrow balance");
        assertEq(userBorrowBalance.inP2P, expectedBorrowBalanceInP2P, "P2P borrow balance");
        assertEq(
            userBorrowBalance.totalBalance,
            expectedTotalBorrowBalance,
            "Total borrow balance"
        );
    }

    function testUserBalanceWithMatching() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        uint256 toMatch = toBorrow / 2;
        supplier1.approve(usdc, toMatch);
        supplier1.supply(cUsdc, toMatch);

        // borrower 1 supply balance (not matched)
        UserBalance memory userSupplyBalance;

        (userSupplyBalance.onPool, userSupplyBalance.inP2P, userSupplyBalance.totalBalance) = lens
        .getCurrentSupplyBalanceInOf(cDai, address(borrower1));

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.mul(morpho.p2pSupplyIndex(cDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.mul(
            ICToken(cDai).exchangeRateCurrent()
        );

        assertEq(userSupplyBalance.onPool, expectedSupplyBalanceOnPool, "On pool supply balance");
        assertEq(userSupplyBalance.inP2P, expectedSupplyBalanceInP2P, "P2P supply balance");
        assertEq(
            userSupplyBalance.totalBalance,
            expectedSupplyBalanceOnPool + expectedSupplyBalanceInP2P,
            "Total supply balance"
        );

        // borrower 1 borrow balance (partially matched)
        UserBalance memory userBorrowBalance;

        (userBorrowBalance.onPool, userBorrowBalance.inP2P, userBorrowBalance.totalBalance) = lens
        .getCurrentBorrowBalanceInOf(cUsdc, address(borrower1));

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.mul(morpho.p2pBorrowIndex(cUsdc));
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.mul(ICToken(cUsdc).borrowIndex());

        assertEq(userBorrowBalance.onPool, expectedBorrowBalanceOnPool, "On pool borrow balance");
        assertEq(userBorrowBalance.inP2P, expectedBorrowBalanceInP2P, "P2P borrow balance");
        assertEq(
            userBorrowBalance.totalBalance,
            expectedBorrowBalanceOnPool + expectedBorrowBalanceInP2P,
            "Total borrow balance"
        );

        // borrower 2 supply balance (pure supplier fully matched)
        UserBalance memory matchedSupplierSupplyBalance;

        (
            matchedSupplierSupplyBalance.onPool,
            matchedSupplierSupplyBalance.inP2P,
            matchedSupplierSupplyBalance.totalBalance
        ) = lens.getCurrentSupplyBalanceInOf(cUsdc, address(supplier1));

        (supplyBalanceInP2P, supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            cUsdc,
            address(supplier1)
        );

        expectedSupplyBalanceInP2P = supplyBalanceInP2P.mul(morpho.p2pSupplyIndex(cUsdc));
        expectedSupplyBalanceOnPool = supplyBalanceOnPool.mul(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(
            matchedSupplierSupplyBalance.onPool,
            expectedSupplyBalanceOnPool,
            "On pool matched supplier balance"
        );
        assertEq(
            matchedSupplierSupplyBalance.inP2P,
            expectedSupplyBalanceInP2P,
            "P2P matched supplier balance"
        );
        assertEq(
            matchedSupplierSupplyBalance.totalBalance,
            expectedSupplyBalanceOnPool + expectedSupplyBalanceInP2P,
            "Total matched supplier balance"
        );
    }

    function testMaxCapacitiesWithNothingWithSupplyWithMultipleAssetsAndBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        Types.AssetLiquidityData memory assetDataCUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            true,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            true,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCUsdt = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdt,
            true,
            oracle
        );

        (uint256 withdrawableDai, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);
        (uint256 withdrawableUsdc, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdc);
        (, uint256 borrowableUsdt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdt);

        uint256 expectedBorrowableUsdt = (assetDataCDai.maxDebtUsd + assetDataCUsdc.maxDebtUsd).div(
            assetDataCUsdt.underlyingPrice
        );

        assertEq(
            withdrawableUsdc,
            getBalanceOnCompound(to6Decimals(amount), ICToken(cUsdc).exchangeRateCurrent()),
            "withdrawable USDC"
        );
        assertApproxEqAbs(
            withdrawableDai,
            getBalanceOnCompound(amount, ICToken(cDai).exchangeRateCurrent()),
            1,
            "withdrawable DAI"
        );
        assertEq(borrowableUsdt, expectedBorrowableUsdt, "borrowable USDT before");

        uint256 toBorrow = to6Decimals(100 ether);
        borrower1.borrow(cUsdt, toBorrow);

        (, uint256 newBorrowableUsdt) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdt
        );

        expectedBorrowableUsdt -= toBorrow;

        assertApproxEqAbs(newBorrowableUsdt, expectedBorrowableUsdt, 1, "borrowable USDT after");
    }

    function testUserBalanceStatesWithSupplyAndBorrow() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (states.collateralUsd, states.debtUsd, states.maxDebtUsd) = lens.getUserBalanceStates(
            address(borrower1),
            new address[](0)
        );

        uint256 underlyingPriceUsdc = oracle.getUnderlyingPrice(cUsdc);

        // DAI data
        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPriceDai = oracle.getUnderlyingPrice(cDai);
        expectedStates.collateralUsd = getBalanceOnCompound(
            amount,
            ICToken(cDai).exchangeRateStored()
        ).mul(underlyingPriceDai);

        expectedStates.debtUsd = getBalanceOnCompound(toBorrow, ICToken(cUsdc).borrowIndex()).mul(
            underlyingPriceUsdc
        );
        expectedStates.maxDebtUsd = expectedStates.collateralUsd.mul(collateralFactor);

        assertEq(states.collateralUsd, expectedStates.collateralUsd, "Collateral Value");
        assertEq(states.maxDebtUsd, expectedStates.maxDebtUsd, "Max Debt Value");
        assertEq(states.debtUsd, expectedStates.debtUsd, "Debt Value");
    }

    function testUserBalanceStatesWithSupplyAndBorrowWithMultipleAssets() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = 100 ether;

        // Avoid stack too deep error
        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        borrower1.borrow(cBat, toBorrow);
        borrower1.borrow(cUsdt, to6Decimals(toBorrow));

        // USDC data
        uint256 collateralValueToAdd = getBalanceOnCompound(
            to6Decimals(amount),
            ICToken(cUsdc).exchangeRateStored()
        ).mul(oracle.getUnderlyingPrice(cUsdc));
        expectedStates.collateralUsd += collateralValueToAdd;
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);
        expectedStates.maxDebtUsd += collateralValueToAdd.mul(collateralFactor);

        // DAI data
        collateralValueToAdd = getBalanceOnCompound(amount, ICToken(cDai).exchangeRateStored()).mul(
            oracle.getUnderlyingPrice(cDai)
        );
        expectedStates.collateralUsd += collateralValueToAdd;
        (, collateralFactor, ) = comptroller.markets(cDai);
        expectedStates.maxDebtUsd += collateralValueToAdd.mul(collateralFactor);

        // BAT
        expectedStates.debtUsd += getBalanceOnCompound(toBorrow, ICToken(cBat).borrowIndex()).mul(
            oracle.getUnderlyingPrice(cBat)
        );
        // USDT
        expectedStates.debtUsd += getBalanceOnCompound(
            to6Decimals(toBorrow),
            ICToken(cUsdt).borrowIndex()
        ).mul(oracle.getUnderlyingPrice(cUsdt));

        (states.collateralUsd, states.debtUsd, states.maxDebtUsd) = lens.getUserBalanceStates(
            address(borrower1),
            new address[](0)
        );

        assertEq(states.collateralUsd, expectedStates.collateralUsd, "Collateral Value");
        assertEq(states.debtUsd, expectedStates.debtUsd, "Debt Value");
        assertEq(states.maxDebtUsd, expectedStates.maxDebtUsd, "Max Debt Value");
    }

    /// This test is to check that a call to getUserLiquidityDataForAsset with USDT doesn't end
    ///   with error "Division or modulo by zero", as Compound returns 0 for USDT collateralFactor.
    function testLiquidityDataForUSDT() public {
        uint256 usdtAmount = to6Decimals(10_000 ether);

        deal(usdt, address(borrower1), usdtAmount);
        borrower1.approve(usdt, usdtAmount);
        borrower1.supply(cUsdt, usdtAmount);

        (uint256 withdrawableUsdt, uint256 borrowableUsdt) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdt
        );

        uint256 depositedUsdtAmount = getBalanceOnCompound(
            usdtAmount,
            ICToken(cUsdt).exchangeRateStored()
        );

        assertEq(withdrawableUsdt, depositedUsdtAmount, "withdrawable USDT");
        assertEq(borrowableUsdt, 0, "borrowable USDT");

        (uint256 withdrawableDai, uint256 borrowableDai) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        assertEq(withdrawableDai, 0, "withdrawable DAI");
        assertEq(borrowableDai, 0, "borrowable DAI");
    }

    function testLiquidityDataFailsWhenOracleFails() public {
        uint256 daiAmount = 1 ether;

        borrower1.approve(dai, daiAmount);
        borrower1.supply(cDai, daiAmount);

        createAndSetCustomPriceOracle().setDirectPrice(dai, 0);

        hevm.expectRevert(abi.encodeWithSignature("CompoundOracleFailed()"));
        lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);
    }

    function testLiquidityDataWithMultipleAssetsAndUSDT() public {
        Indexes memory indexes;
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(100 ether);

        deal(usdt, address(borrower1), to6Decimals(amount));
        borrower1.approve(usdt, to6Decimals(amount));
        indexes.index1 = ICToken(cUsdt).exchangeRateCurrent();
        borrower1.supply(cUsdt, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        borrower1.borrow(cUsdc, toBorrow);
        indexes.index2 = ICToken(cUsdt).exchangeRateCurrent();
        borrower1.borrow(cUsdt, toBorrow);

        // Avoid stack too deep error.
        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (states.collateralUsd, states.debtUsd, states.maxDebtUsd) = lens.getUserBalanceStates(
            address(borrower1),
            new address[](0)
        );

        // We must take into account that not everything is on pool as borrower1 is matched to itself.
        uint256 total;

        {
            uint256 onPool = to6Decimals(amount).div(indexes.index1);
            uint256 matchedInP2P = toBorrow.div(morpho.p2pSupplyIndex(cUsdt));
            uint256 onPoolAfter = onPool - toBorrow.div(indexes.index2);
            total =
                onPoolAfter.mul(indexes.index2) +
                matchedInP2P.mul(morpho.p2pSupplyIndex(cUsdt));
        }

        // USDT data
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdt);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cUsdt);

        uint256 collateralValueToAdd = total.mul(underlyingPrice);
        expectedStates.collateralUsd += collateralValueToAdd;
        expectedStates.maxDebtUsd += collateralValueToAdd.mul(collateralFactor);

        // DAI data
        (, collateralFactor, ) = comptroller.markets(cDai);
        collateralValueToAdd = getBalanceOnCompound(amount, ICToken(cDai).exchangeRateCurrent())
        .mul(oracle.getUnderlyingPrice(cDai));
        expectedStates.collateralUsd += collateralValueToAdd;
        expectedStates.maxDebtUsd += collateralValueToAdd.mul(collateralFactor);

        // USDC data
        expectedStates.debtUsd += getBalanceOnCompound(toBorrow, ICToken(cUsdc).borrowIndex()).mul(
            oracle.getUnderlyingPrice(cUsdc)
        );

        // USDT data
        expectedStates.debtUsd += getBalanceOnCompound(toBorrow, ICToken(cUsdt).borrowIndex()).mul(
            oracle.getUnderlyingPrice(cUsdt)
        );

        assertEq(states.collateralUsd, expectedStates.collateralUsd, "Collateral Value");
        assertEq(states.debtUsd, expectedStates.debtUsd, "Debt Value");
        assertEq(states.maxDebtUsd, expectedStates.maxDebtUsd, "Max Debt Value");
    }

    function testUserHypotheticalBalanceStatesUnenteredMarket() public {
        uint256 amount = 10_001 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        uint256 hypotheticalBorrow = 500e6;
        (uint256 debtValue, uint256 maxDebtValue) = lens.getUserHypotheticalBalanceStates(
            address(borrower1),
            cUsdc,
            amount / 2,
            hypotheticalBorrow
        );

        (, uint256 daiCollateralFactor, ) = comptroller.markets(cDai);

        assertApproxEqAbs(
            maxDebtValue,
            amount.mul(oracle.getUnderlyingPrice(cDai)).mul(daiCollateralFactor),
            1e9,
            "maxDebtValue"
        );
        assertEq(debtValue, hypotheticalBorrow.mul(oracle.getUnderlyingPrice(cUsdc)), "debtValue");
    }

    function testUserHypotheticalBalanceStatesAfterUnauthorisedBorrowWithdraw() public {
        uint256 amount = 10_001 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        uint256 hypotheticalWithdraw = 2 * amount;
        uint256 hypotheticalBorrow = amount;
        (uint256 debtValue, uint256 maxDebtValue) = lens.getUserHypotheticalBalanceStates(
            address(borrower1),
            cDai,
            hypotheticalWithdraw,
            hypotheticalBorrow
        );

        assertEq(maxDebtValue, 0, "maxDebtValue");
        assertEq(debtValue, hypotheticalBorrow.mul(oracle.getUnderlyingPrice(cDai)), "debtValue");
    }

    function testGetMainMarketData() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cDai, amount / 2);

        (
            ,
            ,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount,
            uint256 poolSupplyAmount,
            uint256 poolBorrowAmount
        ) = lens.getMainMarketData(cDai);

        assertApproxEqAbs(p2pSupplyAmount, p2pBorrowAmount, 1e9);
        assertApproxEqAbs(p2pSupplyAmount, amount / 2, 1e9);
        assertApproxEqAbs(poolSupplyAmount, amount / 2, 1e9);
        assertApproxEqAbs(poolBorrowAmount, 0, 1e4);
    }

    function testGetMarketConfiguration() public {
        (
            address underlying,
            bool isCreated,
            bool p2pDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint16 reserveFactor,
            uint16 p2pIndexCursor,
            uint256 collateralFactor
        ) = lens.getMarketConfiguration(cDai);
        assertTrue(underlying == ICToken(cDai).underlying());

        (bool isCreated_, bool isPaused_, bool isPartiallyPaused_) = morpho.marketStatus(cDai);

        assertTrue(isCreated == isCreated_);
        assertTrue(p2pDisabled == morpho.p2pDisabled(cDai));

        assertTrue(isPaused == isPaused_);
        assertTrue(isPartiallyPaused == isPartiallyPaused_);
        (uint16 expectedReserveFactor, uint16 expectedP2PIndexCursor) = morpho.marketParameters(
            cDai
        );
        assertTrue(reserveFactor == expectedReserveFactor);
        assertTrue(p2pIndexCursor == expectedP2PIndexCursor);
        (, uint256 expectedCollateralFactor, ) = morpho.comptroller().markets(cDai);
        assertTrue(collateralFactor == expectedCollateralFactor);
    }

    function testGetOutdatedIndexes() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + (31 * 24 * 60 * 4));
        Types.Indexes memory indexes = lens.getIndexes(cDai, false);

        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(cDai),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(cDai),
            "p2p borrow indexes different"
        );

        assertEq(
            indexes.poolSupplyIndex,
            ICToken(cDai).exchangeRateStored(),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            ICToken(cDai).borrowIndex(),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedIndexes() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + (31 * 24 * 60 * 4));
        Types.Indexes memory indexes = lens.getIndexes(cDai, true);

        morpho.updateP2PIndexes(cDai);
        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(cDai),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(cDai),
            "p2p borrow indexes different"
        );

        assertEq(
            indexes.poolSupplyIndex,
            ICToken(cDai).exchangeRateCurrent(),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            ICToken(cDai).borrowIndex(),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedP2PIndexesWithSupplyDelta() public {
        _createSupplyDelta();
        hevm.roll(block.timestamp + (365 * 24 * 60 * 4));
        Types.Indexes memory indexes = lens.getIndexes(cDai, true);

        morpho.updateP2PIndexes(cDai);
        assertApproxEqAbs(indexes.p2pBorrowIndex, morpho.p2pBorrowIndex(cDai), 1);
        assertApproxEqAbs(indexes.p2pSupplyIndex, morpho.p2pSupplyIndex(cDai), 1);
    }

    function testGetUpdatedP2PIndexesWithBorrowDelta() public {
        _createBorrowDelta();
        hevm.roll(block.timestamp + (365 * 24 * 60 * 4));
        Types.Indexes memory indexes = lens.getIndexes(cDai, true);

        morpho.updateP2PIndexes(cDai);
        assertApproxEqAbs(indexes.p2pBorrowIndex, morpho.p2pBorrowIndex(cDai), 1);
        assertApproxEqAbs(indexes.p2pSupplyIndex, morpho.p2pSupplyIndex(cDai), 1);
    }

    function testGetUpdatedP2PSupplyIndex() public {
        hevm.roll(block.number + (24 * 60 * 4));
        uint256 p2pSupplyIndex = lens.getCurrentP2PSupplyIndex(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(p2pSupplyIndex, morpho.p2pSupplyIndex(cDai));
    }

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.roll(block.number + (24 * 60 * 4));
        uint256 p2pBorrowIndex = lens.getCurrentP2PBorrowIndex(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(cDai));
    }

    function testGetUpdatedP2PBorrowIndexWithDelta() public {
        _createBorrowDelta();
        hevm.roll(block.number + (365 * 24 * 60 * 4));
        uint256 p2pBorrowIndex = lens.getCurrentP2PBorrowIndex(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(cDai));
    }

    function testGetUpdatedIndexesWithTransferToCTokenContract() public {
        hevm.roll(block.number + (31 * 24 * 60 * 4));

        hevm.prank(address(supplier1));
        ERC20(dai).transfer(cDai, 100 ether);

        hevm.roll(block.number + 1);

        Types.Indexes memory indexes = lens.getIndexes(cDai, true);

        morpho.updateP2PIndexes(cDai);
        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(cDai),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(cDai),
            "p2p borrow indexes different"
        );
        assertEq(
            indexes.poolSupplyIndex,
            ICToken(cDai).exchangeRateCurrent(),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            ICToken(cDai).borrowIndex(),
            "pool borrow indexes different"
        );
    }

    function _createSupplyDelta() public {
        uint256 amount = 1 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, amount / 2);
        borrower1.borrow(cDai, amount / 4);

        moveOneBlockForwardBorrowRepay();

        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();

        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        borrower1.repay(cDai, type(uint256).max);

        setDefaultMaxGasForMatchingHelper(supply, borrow, withdraw, repay);
    }

    function _createBorrowDelta() public {
        uint256 amount = 1 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, amount / 2);
        borrower1.borrow(cDai, amount / 4);

        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();

        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(cDai, type(uint256).max);

        setDefaultMaxGasForMatchingHelper(supply, borrow, withdraw, repay);
    }

    function testGetAllMarkets() public {
        address[] memory lensMarkets = lens.getAllMarkets();
        address[] memory morphoMarkets = morpho.getAllMarkets();

        for (uint256 i; i < lensMarkets.length; i++) {
            assertEq(morphoMarkets[i], lensMarkets[i]);
        }
    }

    function testGetEnteredMarkets() public {
        uint256 amount = 1e12;
        supplier1.approve(dai, amount);
        supplier1.approve(usdc, amount);
        supplier1.approve(usdt, amount);
        supplier1.supply(cDai, amount);
        supplier1.supply(cUsdc, amount);
        supplier1.supply(cUsdt, amount);

        address[] memory lensEnteredMarkets = lens.getEnteredMarkets(address(supplier1));
        address[] memory morphoEnteredMarkets = morpho.getEnteredMarkets(address(supplier1));

        for (uint256 i; i < lensEnteredMarkets.length; i++) {
            assertEq(morphoEnteredMarkets[i], lensEnteredMarkets[i]);
        }
    }

    function testIsLiquidatableFalse() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        assertFalse(lens.isLiquidatable(address(borrower1), new address[](0)));
    }

    function testIsLiquidatableTrue() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(usdc, oracle.getUnderlyingPrice(cUsdc) / 2);

        assertTrue(lens.isLiquidatable(address(borrower1), new address[](0)));
    }

    function testHealthFactorBelow1() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setUnderlyingPrice(cUsdc, 0.5e30);
        oracle.setUnderlyingPrice(cDai, 1e18);

        bool isLiquidatable = lens.isLiquidatable(address(borrower1), new address[](0));
        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1), new address[](0));

        assertTrue(isLiquidatable);
        assertLt(healthFactor, 1e18);
    }

    function testHealthFactorAbove1() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setUnderlyingPrice(cUsdc, 1e30);
        oracle.setUnderlyingPrice(cDai, 1e18);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        (, uint256 usdcCollateralFactor, ) = comptroller.markets(cUsdc);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1), new address[](0));
        uint256 expectedHealthFactor = (2 * amount).mul(usdcCollateralFactor).div(amount);

        assertApproxEqAbs(healthFactor, expectedHealthFactor, 1e8);
    }

    function testHealthFactorShouldBeInfinityForPureSuppliers() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(cUsdc, to6Decimals(2 * amount));

        uint256 healthFactor = lens.getUserHealthFactor(address(supplier1), new address[](0));

        assertEq(healthFactor, type(uint256).max);
    }

    function testHealthFactorAbove1WhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setUnderlyingPrice(cUsdc, 1e30);
        oracle.setUnderlyingPrice(cDai, 1e18);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(cDai, amount / 2);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        (, uint256 usdcCollateralFactor, ) = comptroller.markets(cUsdc);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1), new address[](0));
        uint256 expectedHealthFactor = (2 * amount).mul(usdcCollateralFactor).div(amount);

        assertApproxEqAbs(healthFactor, expectedHealthFactor, 1e8);
    }

    function testHealthFactorAbove1WithUpdatedMarkets() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setUnderlyingPrice(cUsdc, 1e30);
        oracle.setUnderlyingPrice(cDai, 1e18);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 10_000);

        address[] memory updatedMarkets = new address[](1);
        uint256 healthFactorNotUpdated = lens.getUserHealthFactor(
            address(borrower1),
            updatedMarkets
        );

        updatedMarkets[0] = cUsdc;

        uint256 healthFactorUsdcUpdated = lens.getUserHealthFactor(
            address(borrower1),
            updatedMarkets
        );

        updatedMarkets[0] = cDai;

        uint256 healthFactorDaiUpdated = lens.getUserHealthFactor(
            address(borrower1),
            updatedMarkets
        );

        assertGt(
            healthFactorUsdcUpdated,
            healthFactorNotUpdated,
            "health factor lower when updating cUsdc"
        );
        assertLt(
            healthFactorDaiUpdated,
            healthFactorNotUpdated,
            "health factor higher when updating cDai"
        );
    }

    function testHealthFactorEqual1() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setUnderlyingPrice(cUsdc, 1e30);
        oracle.setUnderlyingPrice(cDai, 1e18);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        uint256 borrower1HealthFactor = lens.getUserHealthFactor(
            address(borrower1),
            new address[](0)
        );

        borrower2.approve(usdc, to6Decimals(2 * amount));
        borrower2.supply(cUsdc, to6Decimals(2 * amount));
        borrower2.borrow(cDai, amount.mul(borrower1HealthFactor));

        uint256 borrower2HealthFactor = lens.getUserHealthFactor(
            address(borrower2),
            new address[](0)
        );

        assertEq(borrower2HealthFactor, 1e18);
    }

    function testHealthFactorEqual1WhenBorrowingMaxCapacity() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        hevm.roll(block.number + 1000);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        borrower1.borrow(cDai, borrowable);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1), new address[](0));

        assertEq(healthFactor, 1e18);
    }

    function testComputeLiquidation() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(usdc, 1);

        assertEq(
            lens.computeLiquidationRepayAmount(address(borrower1), cDai, cUsdc, new address[](0)),
            0
        );
    }

    function testComputeLiquidation2() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        assertEq(
            lens.computeLiquidationRepayAmount(address(borrower1), cDai, cUsdc, new address[](0)),
            0
        );
    }

    function testComputeLiquidation3() public {
        uint256 amount = 10_000 ether;

        createAndSetCustomPriceOracle().setDirectPrice(
            usdc,
            (oracle.getUnderlyingPrice(cDai) * 2) * 1e12
        );

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.borrow(cDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(
            usdc,
            ((oracle.getUnderlyingPrice(cDai) * 79) / 100) * 1e12
        );

        assertApproxEqAbs(
            lens.computeLiquidationRepayAmount(address(borrower1), cDai, cUsdc, new address[](0)),
            amount.mul(comptroller.closeFactorMantissa()),
            1
        );
    }

    function testComputeLiquidation4() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(
            usdc,
            (oracle.getUnderlyingPrice(cDai) / 2) * 1e12 // Setting the value of the collateral at the same value as the debt.
        );

        assertTrue(lens.isLiquidatable(address(borrower1), new address[](0)));

        assertApproxEqAbs(
            lens.computeLiquidationRepayAmount(address(borrower1), cDai, cUsdc, new address[](0)),
            amount / 2,
            1
        );
    }

    function testLiquidationWithUpdatedPoolIndexes() public {
        uint256 amount = 10_000 ether;

        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.borrow(cDai, amount.mul(collateralFactor) - 10 ether);

        address[] memory updatedMarkets = new address[](2);
        assertFalse(
            lens.isLiquidatable(address(borrower1), updatedMarkets),
            "borrower is already liquidatable"
        );

        hevm.roll(block.number + (31 * 24 * 60 * 4));

        assertFalse(
            lens.isLiquidatable(address(borrower1), updatedMarkets),
            "borrower is already liquidatable"
        );

        updatedMarkets[0] = address(cDai);
        updatedMarkets[1] = address(cUsdc);
        assertTrue(
            lens.isLiquidatable(address(borrower1), updatedMarkets),
            "borrower is not liquidatable with virtually updated pool indexes"
        );

        ICToken(cUsdc).accrueInterest();
        ICToken(cDai).accrueInterest();
        assertTrue(
            lens.isLiquidatable(address(borrower1), new address[](0)),
            "borrower is not liquidatable with updated pool indexes"
        );
    }

    function testLiquidatableWithUpdatedP2PIndexes() public {
        uint256 amount = 10_000 ether;

        supplier2.approve(dai, amount);
        supplier2.supply(cDai, amount);

        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.borrow(cDai, amount.mul(collateralFactor) - 5 ether);

        address[] memory updatedMarkets = new address[](2);
        assertFalse(
            lens.isLiquidatable(address(borrower1), updatedMarkets),
            "borrower is already liquidatable"
        );

        hevm.roll(block.number + (31 * 24 * 60 * 4));

        assertFalse(
            lens.isLiquidatable(address(borrower1), updatedMarkets),
            "borrower is already liquidatable"
        );

        updatedMarkets[0] = address(cDai);
        updatedMarkets[1] = address(cUsdc);
        assertTrue(
            lens.isLiquidatable(address(borrower1), updatedMarkets),
            "borrower is not liquidatable with virtually updated p2p indexes"
        );

        morpho.updateP2PIndexes(cUsdc);
        morpho.updateP2PIndexes(cDai);
        assertTrue(
            lens.isLiquidatable(address(borrower1), new address[](0)),
            "borrower is not liquidatable with updated p2p indexes"
        );
    }

    function testLiquidation(uint256 _amount, uint80 _collateralPrice) internal {
        uint256 amount = _amount + 1e14;
        uint256 collateralPrice = uint256(_collateralPrice) + 1;

        // this is necessary to avoid compound reverting redeem because amount in USD is near zero
        supplier2.approve(usdc, 100e6);
        supplier2.supply(cUsdc, 100e6);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier1));

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(cDai, 2 * amount);
        borrower1.borrow(cUsdc, to6Decimals(amount));

        moveOneBlockForwardBorrowRepay();
        createAndSetCustomPriceOracle().setDirectPrice(dai, collateralPrice);

        (uint256 collateralValue, uint256 debtValue, uint256 maxDebtValue) = lens
        .getUserBalanceStates(address(borrower1), new address[](0));

        uint256 borrowedPrice = oracle.getUnderlyingPrice(cUsdc);
        uint256 toRepay = lens.computeLiquidationRepayAmount(
            address(borrower1),
            cUsdc,
            cDai,
            new address[](0)
        );

        if (debtValue <= maxDebtValue) {
            assertEq(toRepay, 0, "Should return 0 when the position is solvent");
            return;
        }

        if (toRepay != 0) {
            supplier1.approve(usdc, type(uint256).max);

            do {
                supplier1.liquidate(cUsdc, cDai, address(borrower1), toRepay);
                assertGt(
                    ERC20(dai).balanceOf(address(supplier1)),
                    balanceBefore,
                    "balance did not increase"
                );

                balanceBefore = ERC20(dai).balanceOf(address(supplier1));
                toRepay = lens.computeLiquidationRepayAmount(
                    address(borrower1),
                    cUsdc,
                    cDai,
                    new address[](0)
                );
            } while (lens.isLiquidatable(address(borrower1), new address[](0)) && toRepay > 0);

            // either the liquidatee's position (borrow value divided by supply value) was under the [1 / liquidationIncentive] threshold and returned to a solvent position
            if (collateralValue.div(comptroller.liquidationIncentiveMantissa()) > debtValue) {
                assertFalse(lens.isLiquidatable(address(borrower1), new address[](0)));
            } else {
                // or the liquidator has drained all the collateral
                (collateralValue, , ) = lens.getUserBalanceStates(
                    address(borrower1),
                    new address[](0)
                );
                assertApproxEqAbs(
                    collateralValue.div(borrowedPrice).div(
                        comptroller.liquidationIncentiveMantissa()
                    ),
                    0,
                    1
                );
                assertEq(toRepay, 0);
            }
        } else {
            // liquidator cannot repay anything iff 1 wei of borrow is greater than the repayable collateral + the liquidation bonus
            assertEq(
                collateralValue.div(borrowedPrice).div(comptroller.liquidationIncentiveMantissa()),
                0
            );
        }
    }

    function testFuzzLiquidation(uint64 _amount, uint80 _collateralPrice) public {
        testLiquidation(uint256(_amount), _collateralPrice);
    }

    function testFuzzLiquidationUnderIncentiveThreshold(uint64 _amount) public {
        testLiquidation(uint256(_amount), 0.501 ether);
    }

    function testFuzzLiquidationAboveIncentiveThreshold(uint64 _amount) public {
        testLiquidation(uint256(_amount), 0.55 ether);
    }

    /**
     * @dev Because of rounding errors, a liquidatable position worth less than 1e-5 USD cannot get liquidated in practice
     * Explanation with amount = 1e13 (1e-5 USDC borrowed):
     * 0. Before changing the collateralPrice, position is not liquidatable:
     * - debtValue = 9e-6 USD (compound rounding error, should be 1e-5 USD)
     * - collateralValue = 2e-5 USD (+ some dust because of rounding errors, should be 2e-5 USD)
     * 1. collateralPrice is set to 0.501 ether, position is under the [1 / liquidationIncentive] threshold:
     * - debtValue = 9e-6 USD (compound rounding error, should be 1e-5 USD => position should be above the [1 / liquidationIncentive] threshold)
     * - collateralValue = 1.001e-5 USD
     * 2. Liquidation happens, position is now above the [1 / liquidationIncentive] threshold:
     * - toRepay = 4e-6 USD (debtValue * closeFactor = 4.5e-6 truncated to 4e-6)
     * - debtValue = 6e-6 (because of p2p units rounding errors: 9e-6 - 4e-6 ~= 6e-6)
     * 3. After several liquidations, the position is still considered liquidatable but no collateral can be liquidated:
     * - debtValue = 1e-6 USD
     * - collateralValue = 1e-6 USD (+ some dust)
     */
    function testNoRepayLiquidation() public {
        testLiquidation(0, 0.5 ether);
    }

    function testIsLiquidatableDeprecatedMarket() public {
        uint256 amount = 1_000 ether;

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(cDai, 2 * amount);
        borrower1.borrow(cUsdc, to6Decimals(amount));

        assertFalse(lens.isLiquidatable(address(borrower1), cUsdc, new address[](0)));

        morpho.setIsBorrowPaused(cUsdc, true);
        morpho.setIsDeprecated(cUsdc, true);

        assertTrue(lens.isLiquidatable(address(borrower1), cUsdc, new address[](0)));
    }

    struct Amounts {
        uint256 totalP2PSupply;
        uint256 totalPoolSupply;
        uint256 totalSupply;
        uint256 totalP2PBorrow;
        uint256 totalPoolBorrow;
        uint256 totalBorrow;
        uint256 daiP2PSupply;
        uint256 daiPoolSupply;
        uint256 daiP2PBorrow;
        uint256 daiPoolBorrow;
        uint256 ethP2PSupply;
        uint256 ethPoolSupply;
        uint256 ethP2PBorrow;
        uint256 ethPoolBorrow;
    }

    struct SupplyBorrowIndexes {
        uint256 ethPoolSupplyIndexBefore;
        uint256 daiP2PSupplyIndexBefore;
        uint256 daiP2PBorrowIndexBefore;
        uint256 ethPoolSupplyIndexAfter;
        uint256 daiPoolSupplyIndexAfter;
        uint256 daiP2PSupplyIndexAfter;
        uint256 daiP2PBorrowIndexAfter;
    }

    function testTotalSupplyBorrowWithHalfSupplyDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        SupplyBorrowIndexes memory indexes;
        indexes.ethPoolSupplyIndexBefore = ICToken(cEth).exchangeRateCurrent();
        indexes.daiP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cDai);

        hevm.roll(block.number + 1);

        borrower1.approve(dai, amount / 2);
        borrower1.repay(cDai, amount / 2);

        {
            SimplePriceOracle oracle = createAndSetCustomPriceOracle();
            oracle.setUnderlyingPrice(cEth, 2 ether);
            oracle.setUnderlyingPrice(cDai, 1 ether);
        }

        Amounts memory amounts;

        (amounts.totalP2PSupply, amounts.totalPoolSupply, amounts.totalSupply) = lens
        .getTotalSupply();
        (amounts.totalP2PBorrow, amounts.totalPoolBorrow, amounts.totalBorrow) = lens
        .getTotalBorrow();

        (amounts.daiP2PSupply, amounts.daiPoolSupply) = lens.getTotalMarketSupply(cDai);
        (amounts.daiP2PBorrow, amounts.daiPoolBorrow) = lens.getTotalMarketBorrow(cDai);
        (amounts.ethP2PSupply, amounts.ethPoolSupply) = lens.getTotalMarketSupply(cEth);
        (amounts.ethP2PBorrow, amounts.ethPoolBorrow) = lens.getTotalMarketBorrow(cEth);

        indexes.ethPoolSupplyIndexAfter = ICToken(cEth).exchangeRateCurrent();
        indexes.daiPoolSupplyIndexAfter = ICToken(cDai).exchangeRateCurrent();
        indexes.daiP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cDai);

        uint256 expectedDaiUSDOnPool = (amount / 2).div(indexes.daiPoolSupplyIndexAfter).mul(
            indexes.daiPoolSupplyIndexAfter
        ); // which is also the supply delta
        uint256 expectedDaiUSDInP2P = amount.div(indexes.daiP2PBorrowIndexBefore).mul(
            indexes.daiP2PBorrowIndexAfter
        ) - expectedDaiUSDOnPool;
        uint256 expectedEthUSDOnPool = 2 *
            amount.div(indexes.ethPoolSupplyIndexBefore).mul(indexes.ethPoolSupplyIndexAfter);

        assertEq(
            amounts.totalSupply,
            expectedEthUSDOnPool + expectedDaiUSDInP2P + expectedDaiUSDOnPool,
            "unexpected total supply"
        );
        assertApproxEqAbs(amounts.totalBorrow, expectedDaiUSDInP2P, 1e9, "unexpected total borrow");

        assertEq(amounts.totalP2PSupply, expectedDaiUSDInP2P, "unexpected total p2p supply");
        assertEq(
            amounts.totalPoolSupply,
            expectedDaiUSDOnPool + expectedEthUSDOnPool,
            "unexpected total pool supply"
        );
        assertApproxEqAbs(
            amounts.totalP2PBorrow,
            expectedDaiUSDInP2P,
            1e9,
            "unexpected total p2p borrow"
        );
        assertEq(amounts.totalPoolBorrow, 0, "unexpected total pool borrow");

        assertEq(amounts.daiP2PSupply, expectedDaiUSDInP2P, "unexpected dai p2p supply");
        assertApproxEqAbs(
            amounts.daiP2PBorrow,
            expectedDaiUSDInP2P,
            1e9,
            "unexpected dai p2p borrow"
        );
        assertEq(amounts.daiPoolSupply, expectedDaiUSDOnPool, "unexpected dai pool supply");
        assertEq(amounts.daiPoolBorrow, 0, "unexpected dai pool borrow");

        assertEq(amounts.ethP2PSupply, 0, "unexpected eth p2p supply");
        assertEq(amounts.ethP2PBorrow, 0, "unexpected eth p2p borrow");
        assertEq(amounts.ethPoolSupply, expectedEthUSDOnPool / 2, "unexpected eth pool supply");
        assertEq(amounts.ethPoolBorrow, 0, "unexpected eth pool borrow");
    }

    function testTotalSupplyBorrowWithHalfBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        SupplyBorrowIndexes memory indexes;
        indexes.ethPoolSupplyIndexBefore = ICToken(cEth).exchangeRateCurrent();
        indexes.daiP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cDai);

        hevm.roll(block.number + 1);

        supplier1.withdraw(cDai, amount / 2);

        {
            SimplePriceOracle oracle = createAndSetCustomPriceOracle();
            oracle.setUnderlyingPrice(cEth, 2 ether);
            oracle.setUnderlyingPrice(cDai, 1 ether);
        }

        Amounts memory amounts;

        (amounts.totalP2PSupply, amounts.totalPoolSupply, amounts.totalSupply) = lens
        .getTotalSupply();
        (amounts.totalP2PBorrow, amounts.totalPoolBorrow, amounts.totalBorrow) = lens
        .getTotalBorrow();

        (amounts.daiP2PSupply, amounts.daiPoolSupply) = lens.getTotalMarketSupply(cDai);
        (amounts.daiP2PBorrow, amounts.daiPoolBorrow) = lens.getTotalMarketBorrow(cDai);
        (amounts.ethP2PSupply, amounts.ethPoolSupply) = lens.getTotalMarketSupply(cEth);
        (amounts.ethP2PBorrow, amounts.ethPoolBorrow) = lens.getTotalMarketBorrow(cEth);

        indexes.ethPoolSupplyIndexAfter = ICToken(cEth).exchangeRateCurrent();
        indexes.daiPoolSupplyIndexAfter = ICToken(cDai).exchangeRateCurrent();
        indexes.daiP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cDai);

        uint256 expectedDaiUSDOnPool = amount / 2; // which is also the borrow delta
        uint256 expectedDaiUSDInP2P = amount.div(indexes.daiP2PSupplyIndexBefore).mul(
            indexes.daiP2PSupplyIndexAfter
        ) - expectedDaiUSDOnPool;
        uint256 expectedEthUSDOnPool = 2 *
            amount.div(indexes.ethPoolSupplyIndexBefore).mul(indexes.ethPoolSupplyIndexAfter);

        assertApproxEqAbs(
            amounts.totalSupply,
            expectedEthUSDOnPool + expectedDaiUSDInP2P,
            1e9,
            "unexpected total supply"
        );
        assertApproxEqAbs(
            amounts.totalBorrow,
            expectedDaiUSDInP2P + expectedDaiUSDOnPool,
            1,
            "unexpected total borrow"
        );

        assertApproxEqAbs(
            amounts.totalP2PSupply,
            expectedDaiUSDInP2P,
            1e9,
            "unexpected total p2p supply"
        );
        assertApproxEqAbs(
            amounts.totalPoolSupply,
            expectedEthUSDOnPool,
            1,
            "unexpected total pool supply"
        );
        assertApproxEqAbs(
            amounts.totalP2PBorrow,
            expectedDaiUSDInP2P,
            1,
            "unexpected total p2p borrow"
        );
        assertEq(amounts.totalPoolBorrow, expectedDaiUSDOnPool, "unexpected total pool borrow");

        assertApproxEqAbs(
            amounts.daiP2PSupply,
            expectedDaiUSDInP2P,
            1e9,
            "unexpected dai p2p supply"
        );
        assertApproxEqAbs(
            amounts.daiP2PBorrow,
            expectedDaiUSDInP2P,
            1,
            "unexpected dai p2p borrow"
        );
        assertEq(amounts.daiPoolSupply, 0, "unexpected dai pool supply");
        assertEq(amounts.daiPoolBorrow, expectedDaiUSDOnPool, "unexpected dai pool borrow");

        assertEq(amounts.ethP2PSupply, 0, "unexpected eth p2p supply");
        assertEq(amounts.ethP2PBorrow, 0, "unexpected eth p2p borrow");
        assertEq(amounts.ethPoolSupply, expectedEthUSDOnPool / 2, "unexpected eth pool supply");
        assertEq(amounts.ethPoolBorrow, 0, "unexpected eth pool borrow");
    }

    function testGetMarketPauseStatusesDeprecatedMarket() public {
        morpho.setIsBorrowPaused(cDai, true);
        morpho.setIsDeprecated(cDai, true);
        assertTrue(lens.getMarketPauseStatus(cDai).isDeprecated);
    }

    function testGetMarketPauseStatusesPauseSupply() public {
        morpho.setIsSupplyPaused(cDai, true);
        assertTrue(lens.getMarketPauseStatus(cDai).isSupplyPaused);
    }

    function testGetMarketPauseStatusesPauseBorrow() public {
        morpho.setIsBorrowPaused(cDai, true);
        assertTrue(lens.getMarketPauseStatus(cDai).isBorrowPaused);
    }

    function testGetMarketPauseStatusesPauseWithdraw() public {
        morpho.setIsWithdrawPaused(cDai, true);
        assertTrue(lens.getMarketPauseStatus(cDai).isWithdrawPaused);
    }

    function testGetMarketPauseStatusesPauseRepay() public {
        morpho.setIsRepayPaused(cDai, true);
        assertTrue(lens.getMarketPauseStatus(cDai).isRepayPaused);
    }

    function testGetMarketPauseStatusesPauseLiquidateOnCollateral() public {
        morpho.setIsLiquidateCollateralPaused(cDai, true);
        assertTrue(lens.getMarketPauseStatus(cDai).isLiquidateCollateralPaused);
    }

    function testGetMarketPauseStatusesPauseLiquidateOnBorrow() public {
        morpho.setIsLiquidateBorrowPaused(cDai, true);
        assertTrue(lens.getMarketPauseStatus(cDai).isLiquidateBorrowPaused);
    }

    function testPoolIndexGrowthInsideBlock() public {
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 1 ether);

        uint256 poolBorrowIndexBefore = lens.getIndexes(cDai, true).poolSupplyIndex;

        vm.prank(address(supplier1));
        ERC20(dai).transfer(cDai, 10_000 ether);

        supplier1.supply(cDai, 1);

        uint256 poolSupplyIndexAfter = lens.getIndexes(cDai, true).poolSupplyIndex;

        assertGt(poolSupplyIndexAfter, poolBorrowIndexBefore);
    }

    function testP2PIndexGrowthInsideBlock() public {
        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(cDai, 1 ether);
        borrower1.borrow(cDai, 0.5 ether);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        // Bypass the borrow repay in the same block by overwritting the storage slot lastBorrowBlock[borrower1].
        hevm.store(address(morpho), keccak256(abi.encode(address(borrower1), 178)), 0);
        // Create delta.
        borrower1.repay(cDai, type(uint256).max);

        uint256 p2pSupplyIndexBefore = lens.getCurrentP2PSupplyIndex(cDai);

        vm.prank(address(supplier1));
        ERC20(dai).transfer(cDai, 10_000 ether);

        uint256 p2pSupplyIndexAfter = lens.getCurrentP2PSupplyIndex(cDai);

        assertGt(p2pSupplyIndexAfter, p2pSupplyIndexBefore);
    }
}
