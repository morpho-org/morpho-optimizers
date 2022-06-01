// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {ReserveConfiguration} from "@contracts/aave/libraries/aave/ReserveConfiguration.sol";

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    struct UserBalanceStates {
        uint256 collateralValue;
        uint256 debtValue;
    }

    function testCheckHealthFactor() public {
        uint256 amount = 10 ether;
        uint256 toBorrow = to6Decimals(5 ether);
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);

        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(morpho));
        Types.LiquidityData memory liquidityData = lens.getUserHypotheticalBalanceStates(
            address(supplier1),
            address(0),
            0,
            0
        );
        assertEq(liquidityData.healthFactor, healthFactor, "after supply");

        supplier1.borrow(aUsdc, toBorrow);
        (, , , , , healthFactor) = lendingPool.getUserAccountData(address(morpho));
        liquidityData = lens.getUserHypotheticalBalanceStates(address(supplier1), address(0), 0, 0);
        assertEq(liquidityData.healthFactor, healthFactor, "after borrow");

        supplier1.withdraw(aDai, 2 ether);
        (, , , , , healthFactor) = lendingPool.getUserAccountData(address(morpho));
        liquidityData = lens.getUserHypotheticalBalanceStates(address(supplier1), address(0), 0, 0);
        assertEq(liquidityData.healthFactor, healthFactor, "after withdraw");

        supplier1.approve(usdc, type(uint256).max);
        supplier1.repay(aUsdc, 2 ether);
        (, , , , , healthFactor) = lendingPool.getUserAccountData(address(morpho));
        liquidityData = lens.getUserHypotheticalBalanceStates(address(supplier1), address(0), 0, 0);
        assertEq(liquidityData.healthFactor, healthFactor, "after repay");
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = lendingPool
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = lendingPool
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = lendingPool
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
        assertApproxEq(assetData.collateralValue, collateralValue, 2, "collateralValue");
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

        ) = lendingPool.getConfiguration(usdc).getParamsMemory();
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

        (
            expectedDataDai.ltv,
            expectedDataDai.liquidationThreshold,
            ,
            reserveDecimalsDai,

        ) = lendingPool.getConfiguration(dai).getParamsMemory();
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

    function testMaxCapicitiesWithNothingWithSupply() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));

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

        assertEq(withdrawable, to6Decimals(amount), "withdrawable USDC");
        assertEq(borrowable, expectedBorrowableUsdc, "borrowable USDC");

        (withdrawable, borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
    }

    function testMaxCapicitiesWithNothingWithSupplyWithMultipleAssetsAndBorrow() public {
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

        uint256 expectedBorrowable = ((assetDataUsdc.collateralValue.percentMul(assetDataUsdc.ltv) +
            assetDataDai.collateralValue.percentMul(assetDataDai.ltv)) * assetDataUsdt.tokenUnit) /
            assetDataUsdt.underlyingPrice;

        assertEq(withdrawableUsdc, to6Decimals(amount), "withdrawableUsdc");
        assertEq(withdrawableDai, amount, "withdrawableDai");
        assertEq(borrowableUsdt, expectedBorrowable, "borrowableUsdt");

        uint256 toBorrow = to6Decimals(100 ether);
        borrower1.borrow(aUsdt, toBorrow);

        (, uint256 newBorrowableUsdt) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdt
        );

        expectedBorrowable -= toBorrow;

        assertEq(newBorrowableUsdt, expectedBorrowable, "newBorrowableUsdt");
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
        (, , , uint256 reserveDecimalsUsdc, ) = lendingPool
        .getConfiguration(usdc)
        .getParamsMemory();
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**reserveDecimalsUsdc;

        // DAI data
        (
            uint256 ltvDai,
            uint256 liquidationThresholdDai,
            ,
            uint256 reserveDecimalsDai,

        ) = lendingPool.getConfiguration(dai).getParamsMemory();
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
        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, ) = lendingPool
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
        (ltv, liquidationThreshold, , reserveDecimals, ) = lendingPool
        .getConfiguration(dai)
        .getParamsMemory();
        collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.liquidationThresholdValue += collateralValueToAdd.percentMul(
            liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueToAdd.percentMul(ltv);

        // WBTC data
        (, , , reserveDecimals, ) = lendingPool.getConfiguration(wbtc).getParamsMemory();
        expectedStates.debtValue +=
            (toBorrowWbtc * oracle.getAssetPrice(wbtc)) /
            10**reserveDecimals;

        // USDT data
        (, , , reserveDecimals, ) = lendingPool.getConfiguration(usdt).getParamsMemory();
        expectedStates.debtValue +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) /
            10**reserveDecimals;

        expectedStates.healthFactor = expectedStates.liquidationThresholdValue.wadDiv(
            expectedStates.debtValue
        );

        assertApproxEq(
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

        tip(usdt, address(borrower1), usdtAmount);
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

        tip(usdt, address(borrower1), to6Decimals(amount));
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
        (ltv, liquidationThreshold, , reserveDecimals, ) = lendingPool
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
        (ltv, liquidationThreshold, , reserveDecimals, ) = lendingPool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 collateralValueDai = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueDai;
        expectedStates.liquidationThresholdValue += collateralValueDai.percentMul(
            liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueDai.percentMul(ltv);

        // USDC data
        (, , , reserveDecimals, ) = lendingPool.getConfiguration(usdc).getParamsMemory();
        expectedStates.debtValue += (toBorrow * oracle.getAssetPrice(usdc)) / 10**reserveDecimals;

        // USDT data
        (, , , reserveDecimals, ) = lendingPool.getConfiguration(usdt).getParamsMemory();
        expectedStates.debtValue += (toBorrow * oracle.getAssetPrice(usdt)) / 10**reserveDecimals;

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

    function testEnteredMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(aDai, 10 ether);

        borrower1.approve(usdc, to6Decimals(10 ether));
        borrower1.supply(aUsdc, to6Decimals(10 ether));

        assertEq(morpho.enteredMarkets(address(borrower1), 0), aDai);
        assertEq(morpho.enteredMarkets(address(borrower1), 1), aUsdc);

        // Borrower1 withdraw, USDC should be the first in enteredMarkets.
        borrower1.withdraw(aDai, 10 ether);

        assertEq(morpho.enteredMarkets(address(borrower1), 0), aUsdc);
    }

    function testGetMarketData() public {
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint32 lastUpdateBlockNumber,
            uint256 p2pSupplyDelta_,
            uint256 p2pBorrowDelta_,
            uint256 p2pSupplyAmount_,
            uint256 p2pBorrowAmount_
        ) = lens.getMarketData(aDai);

        assertEq(p2pSupplyIndex, morpho.p2pSupplyIndex(aDai));
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(aDai));
        (uint32 expectedLastUpdateBlockNumber, , ) = morpho.poolIndexes(aDai);
        assertEq(lastUpdateBlockNumber, expectedLastUpdateBlockNumber);
        (
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount
        ) = morpho.deltas(aDai);

        assertEq(p2pSupplyDelta_, p2pSupplyDelta);
        assertEq(p2pBorrowDelta_, p2pBorrowDelta);
        assertEq(p2pSupplyAmount_, p2pSupplyAmount);
        assertEq(p2pBorrowAmount_, p2pBorrowAmount);
    }

    function testGetMarketConfiguration() public {
        (
            bool isCreated,
            bool p2pDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint256 reserveFactor
        ) = lens.getMarketConfiguration(aDai);

        (bool isCreated_, bool isPaused_, bool isPartiallyPaused_) = morpho.marketStatus(aDai);

        assertTrue(isCreated == isCreated_);
        assertTrue(p2pDisabled == morpho.p2pDisabled(aDai));

        assertTrue(isPaused == isPaused_);
        assertTrue(isPartiallyPaused == isPartiallyPaused_);
        (uint16 expectedReserveFactor, ) = morpho.marketParameters(aDai);
        assertTrue(reserveFactor == expectedReserveFactor);
    }

    function testGetUpdatedP2PIndexes() public {
        hevm.warp(block.timestamp + 365 days);
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = lens.getUpdatedP2PIndexes(aDai);

        morpho.updateP2PIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PSupplyIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PSupplyIndex = lens.getUpdatedP2PSupplyIndex(aDai);

        morpho.updateP2PIndexes(aDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getUpdatedP2PBorrowIndex(aDai);

        morpho.updateP2PIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
    }
}
