// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    struct UserBalanceStates {
        uint256 collateralValue;
        uint256 debtValue;
        uint256 maxDebtValue;
        uint256 liquidationValue;
    }

    struct UserBalance {
        uint256 onPool;
        uint256 inP2P;
        uint256 totalBalance;
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**reserveDecimals;

        assertEq(assetData.liquidationThreshold, liquidationThreshold);
        assertEq(assetData.ltv, ltv);
        assertEq(assetData.reserveDecimals, reserveDecimals);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.tokenUnit, tokenUnit);
        assertEq(assetData.collateralValue, 0);
        assertEq(assetData.debtValue, 0);
    }

    function testUserLiquidityDataForAssetWithSupply() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**reserveDecimals;
        uint256 collateralValue = (amount * underlyingPrice) / tokenUnit;

        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertEq(assetData.collateralValue, collateralValue, "collateralValue");
        assertEq(assetData.debtValue, 0, "debtValue");
    }

    function testUserLiquidityDataForAssetWithSupplyAndBorrow() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 2;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aDai, toBorrow);

        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**reserveDecimals;
        uint256 collateralValue = (amount * underlyingPrice) / tokenUnit;
        uint256 debtValue = (toBorrow * underlyingPrice) / tokenUnit;

        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.reserveDecimals, reserveDecimals, "reserveDecimals");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertApproxEqAbs(assetData.collateralValue, collateralValue, 2, "collateralValue");
        assertEq(assetData.debtValue, debtValue, "debtValue");
    }

    function testUserLiquidityDataForAssetWithSupplyAndBorrowWithMultipleAssets() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        Types.AssetLiquidityData memory assetDataDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        Types.AssetLiquidityData memory assetDataUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aUsdc,
            oracle
        );

        Types.AssetLiquidityData memory expectedDataUsdc;
        uint256 reserveDecimalsUsdc;

        (
            expectedDataUsdc.ltv,
            expectedDataUsdc.liquidationThreshold,
            ,
            reserveDecimalsUsdc,

        ) = pool.getConfiguration(usdc).getParamsMemory();
        expectedDataUsdc.underlyingPrice = oracle.getAssetPrice(usdc);
        expectedDataUsdc.tokenUnit = 10**reserveDecimalsUsdc;
        expectedDataUsdc.debtValue =
            (toBorrow * expectedDataUsdc.underlyingPrice) /
            expectedDataUsdc.tokenUnit;

        assertEq(
            assetDataUsdc.liquidationThreshold,
            expectedDataUsdc.liquidationThreshold,
            "liquidationThresholdUsdc"
        );
        assertEq(assetDataUsdc.ltv, expectedDataUsdc.ltv, "ltvUsdc");
        assertEq(
            assetDataUsdc.underlyingPrice,
            expectedDataUsdc.underlyingPrice,
            "underlyingPriceUsdc"
        );
        assertEq(assetDataUsdc.tokenUnit, expectedDataUsdc.tokenUnit, "tokenUnitUsdc");
        assertEq(assetDataUsdc.collateralValue, 0, "collateralValueUsdc");
        assertEq(assetDataUsdc.debtValue, expectedDataUsdc.debtValue, "debtValueUsdc");

        Types.AssetLiquidityData memory expectedDataDai;
        uint256 reserveDecimalsDai;

        (expectedDataDai.ltv, expectedDataDai.liquidationThreshold, , reserveDecimalsDai, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        expectedDataDai.underlyingPrice = oracle.getAssetPrice(dai);
        expectedDataDai.tokenUnit = 10**reserveDecimalsDai;
        expectedDataDai.collateralValue =
            (amount * expectedDataDai.underlyingPrice) /
            expectedDataDai.tokenUnit;

        assertEq(
            assetDataDai.liquidationThreshold,
            expectedDataDai.liquidationThreshold,
            "liquidationThresholdDai"
        );
        assertEq(assetDataDai.ltv, expectedDataDai.ltv, "ltvDai");
        assertEq(
            assetDataDai.underlyingPrice,
            expectedDataDai.underlyingPrice,
            "underlyingPriceDai"
        );
        assertEq(assetDataDai.tokenUnit, expectedDataDai.tokenUnit, "tokenUnitDai");
        assertEq(
            assetDataDai.collateralValue,
            expectedDataDai.collateralValue,
            "collateralValueDai"
        );
        assertEq(assetDataDai.debtValue, 0, "debtValueDai");
    }

    function testMaxCapicitiesWithNothing() public {
        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

        assertEq(withdrawable, 0);
        assertEq(borrowable, 0);
    }

    function testMaxCapacitiesWithSupply() public {
        uint256 amount = to6Decimals(10000 ether);

        borrower1.approve(usdc, amount);
        borrower1.supply(aUsdc, amount);

        Types.AssetLiquidityData memory assetDataUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aUsdc,
            oracle
        );

        Types.AssetLiquidityData memory assetDataDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        uint256 expectedBorrowableUsdc = (assetDataUsdc.collateralValue.percentMul(
            assetDataUsdc.ltv
        ) * assetDataUsdc.tokenUnit) / assetDataUsdc.underlyingPrice;
        uint256 expectedBorrowableDai = (assetDataUsdc.collateralValue.percentMul(
            assetDataUsdc.ltv
        ) * assetDataDai.tokenUnit) / assetDataDai.underlyingPrice;

        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );

        assertEq(withdrawable, amount, "withdrawable USDC");
        assertEq(borrowable, expectedBorrowableUsdc, "borrowable USDC");

        (withdrawable, borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
    }

    function testUserBalanceWithoutMatching() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        UserBalance memory userSupplyBalance;

        (userSupplyBalance.onPool, userSupplyBalance.inP2P, userSupplyBalance.totalBalance) = lens
        .getCurrentSupplyBalanceInOf(aDai, address(borrower1));

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.rayMul(morpho.p2pSupplyIndex(aDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.rayMul(
            pool.getReserveNormalizedIncome(dai)
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
        .getCurrentBorrowBalanceInOf(aUsdc, address(borrower1));

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.rayMul(
            morpho.p2pBorrowIndex(aUsdc)
        );
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.rayMul(
            pool.getReserveNormalizedVariableDebt(usdc)
        );
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
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        uint256 toMatch = toBorrow / 2;
        supplier1.approve(usdc, toMatch);
        supplier1.supply(aUsdc, toMatch);

        // borrower 1 supply balance (not matched)
        UserBalance memory userSupplyBalance;

        (userSupplyBalance.onPool, userSupplyBalance.inP2P, userSupplyBalance.totalBalance) = lens
        .getCurrentSupplyBalanceInOf(aDai, address(borrower1));

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.rayMul(morpho.p2pSupplyIndex(aDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.rayMul(
            pool.getReserveNormalizedIncome(dai)
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
        .getCurrentBorrowBalanceInOf(aUsdc, address(borrower1));

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.rayMul(
            morpho.p2pBorrowIndex(aUsdc)
        );
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.rayMul(
            pool.getReserveNormalizedVariableDebt(usdc)
        );

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
        ) = lens.getCurrentSupplyBalanceInOf(aUsdc, address(supplier1));

        (supplyBalanceInP2P, supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );

        expectedSupplyBalanceInP2P = supplyBalanceInP2P.rayMul(morpho.p2pSupplyIndex(aUsdc));
        expectedSupplyBalanceOnPool = supplyBalanceOnPool.rayMul(
            pool.getReserveNormalizedIncome(usdc)
        );

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
        borrower1.supply(aUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        Types.AssetLiquidityData memory assetDataUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aUsdc,
            oracle
        );

        Types.AssetLiquidityData memory assetDataDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        Types.AssetLiquidityData memory assetDataUsdt = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aUsdt,
            oracle
        );

        (uint256 withdrawableDai, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);
        (uint256 withdrawableUsdc, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aUsdc);
        (, uint256 borrowableUsdt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aUsdt);

        uint256 expectedBorrowableUsdt = ((assetDataUsdc.collateralValue.percentMul(
            assetDataUsdc.ltv
        ) + assetDataDai.collateralValue.percentMul(assetDataDai.ltv)) * assetDataUsdt.tokenUnit) /
            assetDataUsdt.underlyingPrice;

        assertEq(withdrawableUsdc, to6Decimals(amount), "unexpected new withdrawable usdc");
        assertEq(withdrawableDai, amount, "unexpected new withdrawable dai");
        assertEq(borrowableUsdt, expectedBorrowableUsdt, "unexpected borrowable usdt");

        uint256 toBorrow = to6Decimals(100 ether);
        borrower1.borrow(aUsdt, toBorrow);

        (, uint256 newBorrowableUsdt) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdt
        );

        expectedBorrowableUsdt -= toBorrow;

        assertEq(newBorrowableUsdt, expectedBorrowableUsdt, "unexpected new borrowable usdt");
    }

    function testUserBalanceStatesWithSupplyAndBorrow() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        Types.LiquidityData memory expectedStates;
        Types.LiquidityData memory states = lens.getUserBalanceStates(address(borrower1));

        // USDC data
        (, , , uint256 reserveDecimalsUsdc, ) = pool.getConfiguration(usdc).getParamsMemory();
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**reserveDecimalsUsdc;

        // DAI data
        (uint256 ltvDai, uint256 liquidationThresholdDai, , uint256 reserveDecimalsDai, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPriceDai = oracle.getAssetPrice(dai);
        uint256 tokenUnitDai = 10**reserveDecimalsDai;

        expectedStates.collateralValue = (amount * underlyingPriceDai) / tokenUnitDai;
        expectedStates.debtValue = (toBorrow * underlyingPriceUsdc) / tokenUnitUsdc;
        expectedStates.liquidationThresholdValue = expectedStates.collateralValue.percentMul(
            liquidationThresholdDai
        );
        expectedStates.maxLoanToValue = expectedStates.collateralValue.percentMul(ltvDai);
        expectedStates.healthFactor = expectedStates.liquidationThresholdValue.wadDiv(
            expectedStates.debtValue
        );

        assertEq(states.collateralValue, expectedStates.collateralValue, "collateralValue");
        assertEq(states.debtValue, expectedStates.debtValue, "debtValue");
        assertEq(
            states.liquidationThresholdValue,
            expectedStates.liquidationThresholdValue,
            "liquidationThresholdValue"
        );
        assertEq(states.maxLoanToValue, expectedStates.maxLoanToValue, "maxLoanToValue");
        assertEq(states.healthFactor, expectedStates.healthFactor, "healthFactor");
    }

    function testUserBalanceStatesWithSupplyAndBorrowWithMultipleAssets() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = 100 ether;
        uint256 toBorrowWbtc = to6Decimals(0.001 ether);

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        borrower1.borrow(aWbtc, toBorrowWbtc);
        borrower1.borrow(aUsdt, to6Decimals(toBorrow));

        Types.LiquidityData memory expectedStates;
        Types.LiquidityData memory states = lens.getUserBalanceStates(address(borrower1));

        // USDC data
        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = pool
        .getConfiguration(usdc)
        .getParamsMemory();
        uint256 collateralValueToAdd = (to6Decimals(amount) * oracle.getAssetPrice(usdc)) /
            10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.liquidationThresholdValue += collateralValueToAdd.percentMul(
            liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueToAdd.percentMul(ltv);

        // DAI data
        (ltv, liquidationThreshold, , reserveDecimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.liquidationThresholdValue += collateralValueToAdd.percentMul(
            liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueToAdd.percentMul(ltv);

        // WBTC data
        (, , , reserveDecimals, ) = pool.getConfiguration(wbtc).getParamsMemory();
        expectedStates.debtValue +=
            (toBorrowWbtc * oracle.getAssetPrice(wbtc)) /
            10**reserveDecimals;

        // USDT data
        (, , , reserveDecimals, ) = pool.getConfiguration(usdt).getParamsMemory();
        expectedStates.debtValue +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) /
            10**reserveDecimals;

        expectedStates.healthFactor = expectedStates.liquidationThresholdValue.wadDiv(
            expectedStates.debtValue
        );

        assertApproxEqAbs(
            states.collateralValue,
            expectedStates.collateralValue,
            2,
            "collateralValue"
        );
        assertEq(states.debtValue, expectedStates.debtValue, "debtValue");
        assertEq(
            states.liquidationThresholdValue,
            expectedStates.liquidationThresholdValue,
            "liquidationThresholdValue"
        );
        assertEq(states.maxLoanToValue, expectedStates.maxLoanToValue, "maxLoanToValue");
        assertEq(states.healthFactor, expectedStates.healthFactor, "healthFactor");
    }

    /// This test is to check that a call to getUserLiquidityDataForAsset with USDT doesn't end
    ///   with error "Division or modulo by zero", as Aave returns 0 for USDT liquidationThreshold.
    function testLiquidityDataForUSDT() public {
        uint256 usdtAmount = to6Decimals(10_000 ether);

        deal(usdt, address(borrower1), usdtAmount);
        borrower1.approve(usdt, usdtAmount);
        borrower1.supply(aUsdt, usdtAmount);

        (uint256 withdrawableUsdt, uint256 borrowableUsdt) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdt
        );

        assertEq(withdrawableUsdt, usdtAmount, "withdrawable USDT");
        assertEq(borrowableUsdt, 0, "borrowable USDT");

        (uint256 withdrawableDai, uint256 borrowableDai) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

        assertEq(withdrawableDai, 0, "withdrawable DAI");
        assertEq(borrowableDai, 0, "borrowable DAI");
    }

    function testLiquidityDataWithMultipleAssetsAndUSDT() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(100 ether);

        deal(usdt, address(borrower1), to6Decimals(amount));
        borrower1.approve(usdt, to6Decimals(amount));
        borrower1.supply(aUsdt, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        borrower1.borrow(aUsdc, toBorrow);
        borrower1.borrow(aUsdt, toBorrow);

        uint256 reserveDecimals;
        uint256 ltv;
        uint256 liquidationThreshold;

        Types.LiquidityData memory expectedStates;
        Types.LiquidityData memory states = lens.getUserBalanceStates(address(borrower1));

        // USDT data
        (ltv, liquidationThreshold, , reserveDecimals, ) = pool
        .getConfiguration(usdt)
        .getParamsMemory();
        uint256 collateralValueUsdt = (to6Decimals(amount) * oracle.getAssetPrice(usdt)) /
            10**reserveDecimals;
        expectedStates.collateralValue += collateralValueUsdt;
        expectedStates.liquidationThresholdValue += collateralValueUsdt.percentMul(
            liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueUsdt.percentMul(ltv);

        // DAI data
        (ltv, liquidationThreshold, , reserveDecimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 collateralValueDai = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueDai;
        expectedStates.liquidationThresholdValue += collateralValueDai.percentMul(
            liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueDai.percentMul(ltv);

        // USDC data
        (, , , reserveDecimals, ) = pool.getConfiguration(usdc).getParamsMemory();
        expectedStates.debtValue += (toBorrow * oracle.getAssetPrice(usdc)) / 10**reserveDecimals;

        // USDT data
        (, , , reserveDecimals, ) = pool.getConfiguration(usdt).getParamsMemory();
        expectedStates.debtValue += (toBorrow * oracle.getAssetPrice(usdt)) / 10**reserveDecimals;

        expectedStates.healthFactor = expectedStates.liquidationThresholdValue.wadDiv(
            expectedStates.debtValue
        );

        assertApproxEqAbs(
            states.collateralValue,
            expectedStates.collateralValue,
            1e3,
            "collateralValue"
        );
        assertEq(states.debtValue, expectedStates.debtValue, "debtValue");
        assertEq(
            states.liquidationThresholdValue,
            expectedStates.liquidationThresholdValue,
            "liquidationThresholdValue"
        );
        assertEq(states.maxLoanToValue, expectedStates.maxLoanToValue, "maxLoanToValue");
        assertEq(states.healthFactor, expectedStates.healthFactor, "healthFactor");
    }

    function testGetMainMarketData() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aDai, amount / 2);

        (
            ,
            ,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount,
            uint256 poolSupplyAmount,
            uint256 poolBorrowAmount
        ) = lens.getMainMarketData(aDai);

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
            uint16 p2pIndexCursor
        ) = lens.getMarketConfiguration(aDai);
        assertTrue(underlying == dai);

        (bool isCreated_, bool isPaused_, bool isPartiallyPaused_) = morpho.marketStatus(aDai);

        assertTrue(isCreated == isCreated_);
        assertTrue(p2pDisabled == morpho.p2pDisabled(aDai));

        assertTrue(isPaused == isPaused_);
        assertTrue(isPartiallyPaused == isPartiallyPaused_);
        (uint16 expectedReserveFactor, uint16 expectedP2PIndexCursor) = morpho.marketParameters(
            aDai
        );
        assertTrue(reserveFactor == expectedReserveFactor);
        assertTrue(p2pIndexCursor == expectedP2PIndexCursor);
    }

    function testGetOutdatedIndexes() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + (31 * 24 * 60 * 4));
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 poolSupplyIndex,
            uint256 poolBorrowIndex
        ) = lens.getIndexes(aDai);

        assertEq(p2pSupplyIndex, morpho.p2pSupplyIndex(aDai), "p2p supply indexes different");
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(aDai), "p2p borrow indexes different");

        assertEq(
            poolSupplyIndex,
            pool.getReserveNormalizedIncome(dai),
            "pool supply indexes different"
        );
        assertEq(
            poolBorrowIndex,
            pool.getReserveNormalizedVariableDebt(dai),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedIndexes() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + (31 * 24 * 60 * 4));
        (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        ) = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai), "p2p supply indexes different");
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai), "p2p borrow indexes different");

        assertEq(
            newPoolSupplyIndex,
            pool.getReserveNormalizedIncome(dai),
            "pool supply indexes different"
        );
        assertEq(
            newPoolBorrowIndex,
            pool.getReserveNormalizedVariableDebt(dai),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedP2PIndexesWithSupplyDelta() public {
        _createSupplyDelta();
        hevm.warp(block.timestamp + 365 days);
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex, , ) = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PIndexesWithBorrowDelta() public {
        _createBorrowDelta();
        hevm.warp(block.timestamp + 365 days);
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex, , ) = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PSupplyIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PSupplyIndex = lens.getCurrentP2PSupplyIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PSupplyIndexWithDelta() public {
        _createSupplyDelta();
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PSupplyIndex = lens.getCurrentP2PSupplyIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getCurrentP2PBorrowIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
    }

    function testGetUpdatedP2PBorrowIndexWithDelta() public {
        _createBorrowDelta();
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getCurrentP2PBorrowIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
    }

    function _createSupplyDelta() public {
        uint256 amount = 1 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);
        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, amount / 2);
        borrower1.borrow(aDai, amount / 4);
        _setDefaultMaxGasForMatching(0, 0, 0, 0);
        borrower1.repay(aDai, type(uint256).max);
    }

    function _createBorrowDelta() public {
        uint256 amount = 1 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);
        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, amount / 2);
        borrower1.borrow(aDai, amount / 4);
        _setDefaultMaxGasForMatching(0, 0, 0, 0);
        supplier1.withdraw(aDai, type(uint256).max);
    }

    function testGetAllMarkets() public {
        address[] memory lensMarkets = lens.getAllMarkets();
        address[] memory morphoMarkets = morpho.getMarketsCreated();

        for (uint256 i; i < lensMarkets.length; i++) {
            assertEq(morphoMarkets[i], lensMarkets[i]);
        }
    }

    function testGetEnteredMarkets() public {
        uint256 amount = 1e12;
        supplier1.approve(dai, amount);
        supplier1.approve(usdc, amount);
        supplier1.approve(usdt, amount);
        supplier1.supply(aDai, amount);
        supplier1.supply(aUsdc, amount);
        supplier1.supply(aUsdt, amount);

        address[] memory enteredMarkets = lens.getEnteredMarkets(address(supplier1));
        bytes32 userMarkets = morpho.userMarkets(address(supplier1));

        uint256 j;
        for (uint256 i; i < pools.length; ) {
            address market = pools[i];

            for (j = 0; j < enteredMarkets.length; ) {
                if (enteredMarkets[j] == market) break;

                unchecked {
                    ++j;
                }
            }

            bytes32 marketBitmask = morpho.borrowMask(market);
            if (userMarkets & (marketBitmask | (marketBitmask << 1)) != 0)
                assertLt(j, enteredMarkets.length, "market entered not in enteredMarkets");
            else assertEq(j, enteredMarkets.length, "market not entered in enteredMarkets");

            unchecked {
                ++i;
            }
        }
    }

    // function testIsLiquidatableFalse() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     assertFalse(lens.isLiquidatable(address(borrower1)));
    // }

    // function testIsLiquidatableTrue() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     createAndSetCustomPriceOracle().setDirectPrice(usdc, oracle.getUnderlyingPrice(aUsdc) / 2);

    //     assertTrue(lens.isLiquidatable(address(borrower1)));
    // }

    // function testHealthFactorBelow1() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     SimplePriceOracle oracle = createAndSetCustomPriceOracle();
    //     oracle.setDirectPrice(usdc, 0.6e30);
    //     oracle.setDirectPrice(dai, 1e18);

    //     bool isLiquidatable = lens.isLiquidatable(address(borrower1));
    //     uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

    //     assertTrue(isLiquidatable);
    //     assertLt(healthFactor, 1e18);
    // }

    function testHealthFactorAbove1() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setDirectPrice(usdc, 1e18);
        oracle.setDirectPrice(dai, 1e18);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

        (, uint256 liquidationThreshold, , , ) = pool.getConfiguration(usdc).getParamsMemory();

        assertEq(healthFactor, uint256(2 ether).percentMul(liquidationThreshold));
    }

    function testHealthFactorShouldBeInfinityForPureSuppliers() public {
        uint256 amount = to6Decimals(10_000 ether);

        supplier1.approve(usdc, amount);
        supplier1.supply(aUsdc, amount);

        uint256 healthFactor = lens.getUserHealthFactor(address(supplier1));

        assertEq(healthFactor, type(uint256).max);
    }

    function testHealthFactorAbove1WhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setDirectPrice(usdc, 1e18);
        oracle.setDirectPrice(dai, 1e18);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

        (, uint256 liquidationThreshold, , , ) = pool.getConfiguration(usdc).getParamsMemory();

        assertEq(healthFactor, uint256(2 ether).percentMul(liquidationThreshold));
    }

    function testHealthFactorEqual1() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setDirectPrice(usdc, 1e18);
        oracle.setDirectPrice(dai, 1e18);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 borrower1HealthFactor = lens.getUserHealthFactor(address(borrower1));

        oracle.setDirectPrice(usdc, 2e18); // let borrower2 borrow as much as they want

        borrower2.approve(usdc, to6Decimals(2 * amount));
        borrower2.supply(aUsdc, to6Decimals(2 * amount));
        borrower2.borrow(aDai, amount.wadMul(borrower1HealthFactor));

        oracle.setDirectPrice(usdc, 1e18);

        uint256 borrower2HealthFactor = lens.getUserHealthFactor(address(borrower2));

        assertEq(borrower2HealthFactor, 1e18);
    }

    function testHealthFactorEqual1WhenBorrowingMaxCapacity() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1000);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        borrower1.borrow(aDai, borrowable);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

        (uint256 ltv, uint256 liquidationThreshold, , , ) = pool
        .getConfiguration(usdc)
        .getParamsMemory();

        assertEq(healthFactor, uint256(1 ether).percentMul(liquidationThreshold).percentDiv(ltv));
    }

    // function testComputeLiquidation() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     createAndSetCustomPriceOracle().setDirectPrice(usdc, 1);

    //     assertEq(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc),
    //         0
    //     );
    // }

    // function testComputeLiquidation2() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     assertEq(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc),
    //         0
    //     );
    // }

    // function testComputeLiquidation3() public {
    //     uint256 amount = 10_000 ether;

    //     createAndSetCustomPriceOracle().setDirectPrice(
    //         usdc,
    //         (oracle.getUnderlyingPrice(aDai) * 2) * 1e12
    //     );

    //     borrower1.approve(usdc, to6Decimals(amount));
    //     borrower1.supply(aUsdc, to6Decimals(amount));
    //     borrower1.borrow(aDai, amount);

    //     createAndSetCustomPriceOracle().setDirectPrice(
    //         usdc,
    //         ((oracle.getUnderlyingPrice(aDai) * 79) / 100) * 1e12
    //     );

    //     assertApproxEqAbs(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc),
    //         amount.rayMul(comptroller.closeFactorMantissa()),
    //         1
    //     );
    // }

    // function testComputeLiquidation4() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     createAndSetCustomPriceOracle().setDirectPrice(
    //         usdc,
    //         (oracle.getUnderlyingPrice(aDai) / 2) * 1e12 // Setting the value of the collateral at the same value as the debt.
    //     );

    //     assertTrue(lens.isLiquidatable(address(borrower1)));

    //     assertApproxEqAbs(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc),
    //         amount / 2,
    //         1
    //     );
    // }

    // function testLiquidationWithUpdatedPoolIndexes() public {
    //     uint256 amount = 10_000 ether;

    //     (, uint256 collateralFactor, ) = comptroller.markets(aUsdc);

    //     borrower1.approve(usdc, to6Decimals(amount));
    //     borrower1.supply(aUsdc, to6Decimals(amount));
    //     borrower1.borrow(aDai, amount.rayMul(collateralFactor) - 10 ether);

    //     address[] memory updatedMarkets = new address[](2);
    //     assertFalse(
    //         lens.isLiquidatable(address(borrower1), updatedMarkets),
    //         "borrower is already liquidatable"
    //     );

    //     hevm.roll(block.number + (31 * 24 * 60 * 4));

    //     assertFalse(
    //         lens.isLiquidatable(address(borrower1), updatedMarkets),
    //         "borrower is already liquidatable"
    //     );

    //     updatedMarkets[0] = address(aDai);
    //     updatedMarkets[1] = address(aUsdc);
    //     assertTrue(
    //         lens.isLiquidatable(address(borrower1), updatedMarkets),
    //         "borrower is not liquidatable with virtually updated pool indexes"
    //     );

    //     IAToken(aUsdc).accrueInterest();
    //     IAToken(aDai).accrueInterest();
    //     assertTrue(
    //         lens.isLiquidatable(address(borrower1)),
    //         "borrower is not liquidatable with updated pool indexes"
    //     );
    // }

    // function testLiquidatableWithUpdatedP2PIndexes() public {
    //     uint256 amount = 10_000 ether;

    //     supplier2.approve(dai, amount);
    //     supplier2.supply(aDai, amount);

    //     (, uint256 collateralFactor, ) = comptroller.markets(aUsdc);

    //     borrower1.approve(usdc, to6Decimals(amount));
    //     borrower1.supply(aUsdc, to6Decimals(amount));
    //     borrower1.borrow(aDai, amount.rayMul(collateralFactor) - 10 ether);

    //     address[] memory updatedMarkets = new address[](2);
    //     assertFalse(
    //         lens.isLiquidatable(address(borrower1), updatedMarkets),
    //         "borrower is already liquidatable"
    //     );

    //     hevm.roll(block.number + (31 * 24 * 60 * 4));

    //     assertFalse(
    //         lens.isLiquidatable(address(borrower1), updatedMarkets),
    //         "borrower is already liquidatable"
    //     );

    //     updatedMarkets[0] = address(aDai);
    //     updatedMarkets[1] = address(aUsdc);
    //     assertTrue(
    //         lens.isLiquidatable(address(borrower1), updatedMarkets),
    //         "borrower is not liquidatable with virtually updated p2p indexes"
    //     );

    //     morpho.updateP2PIndexes(aUsdc);
    //     morpho.updateP2PIndexes(aDai);
    //     assertTrue(
    //         lens.isLiquidatable(address(borrower1)),
    //         "borrower is not liquidatable with updated p2p indexes"
    //     );
    // }

    // function testLiquidation(uint256 _amount, uint80 _collateralPrice) internal {
    //     uint256 amount = _amount + 1e14;
    //     uint256 collateralPrice = uint256(_collateralPrice) + 1;

    //     // this is necessary to avoid compound reverting redeem because amount in USD is near zero
    //     supplier2.approve(usdc, 100e6);
    //     supplier2.supply(aUsdc, 100e6);

    //     uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier1));

    //     borrower1.approve(dai, 2 * amount);
    //     borrower1.supply(aDai, 2 * amount);
    //     borrower1.borrow(aUsdc, to6Decimals(amount));

    //     moveOneBlockForwardBorrowRepay();
    //     createAndSetCustomPriceOracle().setDirectPrice(dai, collateralPrice);

    //     (uint256 collateralValue, uint256 debtValue, uint256 maxDebtValue) = lens
    //         .getUserBalanceStates(address(borrower1));

    //     uint256 borrowedPrice = oracle.getUnderlyingPrice(aUsdc);
    //     uint256 toRepay = lens.computeLiquidationRepayAmount(
    //         address(borrower1),
    //         aUsdc,
    //         aDai,
    //         new address[](0)
    //     );

    //     if (debtValue <= maxDebtValue) {
    //         assertEq(toRepay, 0, "Should return 0 when the position is solvent");
    //         return;
    //     }

    //     if (toRepay != 0) {
    //         supplier1.approve(usdc, type(uint256).max);

    //         do {
    //             supplier1.liquidate(aUsdc, aDai, address(borrower1), toRepay);
    //             assertGt(
    //                 ERC20(dai).balanceOf(address(supplier1)),
    //                 balanceBefore,
    //                 "balance did not increase"
    //             );

    //             balanceBefore = ERC20(dai).balanceOf(address(supplier1));
    //             toRepay = lens.computeLiquidationRepayAmount(
    //                 address(borrower1),
    //                 aUsdc,
    //                 aDai,
    //                 new address[](0)
    //             );
    //         } while (lens.isLiquidatable(address(borrower1)) && toRepay > 0);

    //         // either the liquidatee's position (borrow value divided by supply value) was under the [1 / liquidationIncentive] threshold and returned to a solvent position
    //         if (collateralValue.rayDiv(comptroller.liquidationIncentiveMantissa()) > debtValue) {
    //             assertFalse(lens.isLiquidatable(address(borrower1)));
    //         } else {
    //             // or the liquidator has drained all the collateral
    //             (collateralValue, , ) = lens.getUserBalanceStates(
    //                 address(borrower1),
    //                 new address[](0)
    //             );
    //             assertEq(
    //                 collateralValue.rayDiv(borrowedPrice).rayDiv(
    //                     comptroller.liquidationIncentiveMantissa()
    //                 ),
    //                 0
    //             );
    //             assertEq(toRepay, 0);
    //         }
    //     } else {
    //         // liquidator cannot repay anything iff 1 wei of borrow is greater than the repayable collateral + the liquidation bonus
    //         assertEq(
    //             collateralValue.rayDiv(borrowedPrice).rayDiv(comptroller.liquidationIncentiveMantissa()),
    //             0
    //         );
    //     }
    // }

    // function testFuzzLiquidation(uint64 _amount, uint80 _collateralPrice) public {
    //     testLiquidation(uint256(_amount), _collateralPrice);
    // }

    // function testFuzzLiquidationUnderIncentiveThreshold(uint64 _amount) public {
    //     testLiquidation(uint256(_amount), 0.501 ether);
    // }

    // function testFuzzLiquidationAboveIncentiveThreshold(uint64 _amount) public {
    //     testLiquidation(uint256(_amount), 0.55 ether);
    // }

    // /**
    //  * @dev Because of rounding errors, a liquidatable position worth less than 1e-5 USD cannot get liquidated in practice
    //  * Explanation with amount = 1e13 (1e-5 USDC borrowed):
    //  * 0. Before changing the collateralPrice, position is not liquidatable:
    //  * - debtValue = 9e-6 USD (compound rounding error, should be 1e-5 USD)
    //  * - collateralValue = 2e-5 USD (+ some dust because of rounding errors, should be 2e-5 USD)
    //  * 1. collateralPrice is set to 0.501 ether, position is under the [1 / liquidationIncentive] threshold:
    //  * - debtValue = 9e-6 USD (compound rounding error, should be 1e-5 USD => position should be above the [1 / liquidationIncentive] threshold)
    //  * - collateralValue = 1.001e-5 USD
    //  * 2. Liquidation happens, position is now above the [1 / liquidationIncentive] threshold:
    //  * - toRepay = 4e-6 USD (debtValue * closeFactor = 4.5e-6 truncated to 4e-6)
    //  * - debtValue = 6e-6 (because of p2p units rounding errors: 9e-6 - 4e-6 ~= 6e-6)
    //  * 3. After several liquidations, the position is still considered liquidatable but no collateral can be liquidated:
    //  * - debtValue = 1e-6 USD
    //  * - collateralValue = 1e-6 USD (+ some dust)
    //  */
    // function testNoRepayLiquidation() public {
    //     testLiquidation(0, 0.5 ether);
    // }

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

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

        SupplyBorrowIndexes memory indexes;
        indexes.ethPoolSupplyIndexBefore = pool.getReserveNormalizedIncome(aave);
        indexes.daiP2PBorrowIndexBefore = morpho.p2pBorrowIndex(aDai);

        hevm.roll(block.number + 1);

        borrower1.approve(dai, amount / 2);
        borrower1.repay(aDai, amount / 2);

        {
            SimplePriceOracle oracle = createAndSetCustomPriceOracle();
            oracle.setDirectPrice(aave, 2 ether);
            oracle.setDirectPrice(dai, 1 ether);
        }

        Amounts memory amounts;

        (amounts.totalP2PSupply, amounts.totalPoolSupply, amounts.totalSupply) = lens
        .getTotalSupply();
        (amounts.totalP2PBorrow, amounts.totalPoolBorrow, amounts.totalBorrow) = lens
        .getTotalBorrow();

        (amounts.daiP2PSupply, amounts.daiPoolSupply) = lens.getTotalMarketSupply(aDai);
        (amounts.daiP2PBorrow, amounts.daiPoolBorrow) = lens.getTotalMarketBorrow(aDai);
        (amounts.ethP2PSupply, amounts.ethPoolSupply) = lens.getTotalMarketSupply(aAave);
        (amounts.ethP2PBorrow, amounts.ethPoolBorrow) = lens.getTotalMarketBorrow(aAave);

        indexes.ethPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(aave);
        indexes.daiPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(dai);
        indexes.daiP2PBorrowIndexAfter = morpho.p2pBorrowIndex(aDai);

        uint256 expectedDaiUSDOnPool = (amount / 2).rayDiv(indexes.daiPoolSupplyIndexAfter).rayMul(
            indexes.daiPoolSupplyIndexAfter
        ); // which is also the supply delta
        uint256 expectedDaiUSDInP2P = amount.rayDiv(indexes.daiP2PBorrowIndexBefore).rayMul(
            indexes.daiP2PBorrowIndexAfter
        ) - expectedDaiUSDOnPool;
        uint256 expectedEthUSDOnPool = 2 *
            amount.rayDiv(indexes.ethPoolSupplyIndexBefore).rayMul(indexes.ethPoolSupplyIndexAfter);

        assertEq(
            amounts.totalSupply,
            expectedEthUSDOnPool + expectedDaiUSDInP2P + expectedDaiUSDOnPool,
            "unexpected total supply"
        );
        assertApproxEqAbs(amounts.totalBorrow, expectedDaiUSDInP2P, 1e8, "unexpected total borrow");

        assertEq(amounts.totalP2PSupply, expectedDaiUSDInP2P, "unexpected total p2p supply");
        assertEq(
            amounts.totalPoolSupply,
            expectedDaiUSDOnPool + expectedEthUSDOnPool,
            "unexpected total pool supply"
        );
        assertApproxEqAbs(
            amounts.totalP2PBorrow,
            expectedDaiUSDInP2P,
            1e8,
            "unexpected total p2p borrow"
        );
        assertEq(amounts.totalPoolBorrow, 0, "unexpected total pool borrow");

        assertEq(amounts.daiP2PSupply, expectedDaiUSDInP2P, "unexpected dai p2p supply");
        assertApproxEqAbs(
            amounts.daiP2PBorrow,
            expectedDaiUSDInP2P,
            1e8,
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

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        _setDefaultMaxGasForMatching(3e6, 3e6, 0, 0);

        SupplyBorrowIndexes memory indexes;
        indexes.ethPoolSupplyIndexBefore = pool.getReserveNormalizedIncome(aave);
        indexes.daiP2PSupplyIndexBefore = morpho.p2pSupplyIndex(aDai);

        hevm.roll(block.number + 1);

        supplier1.withdraw(aDai, amount / 2);

        {
            SimplePriceOracle oracle = createAndSetCustomPriceOracle();
            oracle.setDirectPrice(aave, 2 ether);
            oracle.setDirectPrice(dai, 1 ether);
        }

        Amounts memory amounts;

        (amounts.totalP2PSupply, amounts.totalPoolSupply, amounts.totalSupply) = lens
        .getTotalSupply();
        (amounts.totalP2PBorrow, amounts.totalPoolBorrow, amounts.totalBorrow) = lens
        .getTotalBorrow();

        (amounts.daiP2PSupply, amounts.daiPoolSupply) = lens.getTotalMarketSupply(aDai);
        (amounts.daiP2PBorrow, amounts.daiPoolBorrow) = lens.getTotalMarketBorrow(aDai);
        (amounts.ethP2PSupply, amounts.ethPoolSupply) = lens.getTotalMarketSupply(aAave);
        (amounts.ethP2PBorrow, amounts.ethPoolBorrow) = lens.getTotalMarketBorrow(aAave);

        indexes.ethPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(aave);
        indexes.daiPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(dai);
        indexes.daiP2PSupplyIndexAfter = morpho.p2pSupplyIndex(aDai);

        uint256 expectedDaiUSDOnPool = amount / 2; // which is also the borrow delta
        uint256 expectedDaiUSDInP2P = amount.rayDiv(indexes.daiP2PSupplyIndexBefore).rayMul(
            indexes.daiP2PSupplyIndexAfter
        ) - expectedDaiUSDOnPool;
        uint256 expectedEthUSDOnPool = 2 *
            amount.rayDiv(indexes.ethPoolSupplyIndexBefore).rayMul(indexes.ethPoolSupplyIndexAfter);

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
}
