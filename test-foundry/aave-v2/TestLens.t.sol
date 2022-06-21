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
    }

    function testCheckHealthFactor() public {
        uint256 amount = 10 ether;
        uint256 toBorrow = to6Decimals(5 ether);
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);

        (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(morpho));
        Types.LiquidityData memory liquidityData = lens.getUserHypotheticalBalanceStates(
            address(supplier1),
            address(0),
            0,
            0
        );
        assertEq(liquidityData.healthFactor, healthFactor, "after supply");

        supplier1.borrow(aUsdc, toBorrow);
        (, , , , , healthFactor) = pool.getUserAccountData(address(morpho));
        liquidityData = lens.getUserHypotheticalBalanceStates(address(supplier1), address(0), 0, 0);
        assertEq(liquidityData.healthFactor, healthFactor, "after borrow");

        supplier1.withdraw(aDai, 2 ether);
        (, , , , , healthFactor) = pool.getUserAccountData(address(morpho));
        liquidityData = lens.getUserHypotheticalBalanceStates(address(supplier1), address(0), 0, 0);
        assertEq(liquidityData.healthFactor, healthFactor, "after withdraw");

        supplier1.approve(usdc, type(uint256).max);
        supplier1.repay(aUsdc, 2 ether);
        (, , , , , healthFactor) = pool.getUserAccountData(address(morpho));
        liquidityData = lens.getUserHypotheticalBalanceStates(address(supplier1), address(0), 0, 0);
        assertEq(liquidityData.healthFactor, healthFactor, "after repay");
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

    function testEnteredMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(aDai, 10 ether);

        borrower1.approve(usdc, to6Decimals(10 ether));
        borrower1.supply(aUsdc, to6Decimals(10 ether));

        assertTrue(isSupplying(address(borrower1), aDai));
        assertTrue(isSupplying(address(borrower1), aUsdc));

        // Borrower1 withdraw, USDC should be the first in enteredMarkets.
        borrower1.withdraw(aDai, type(uint256).max);

        assertFalse(isSupplying(address(borrower1), aDai));
        assertTrue(isSupplying(address(borrower1), aUsdc));
    }

    function isSupplying(address _user, address _market) internal view returns (bool) {
        return morpho.userMarkets(_user) & (morpho.borrowMask(_market) << 1) != 0;
    }

    function testGetMarketData() public {
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint256 p2pSupplyDelta_,
            uint256 p2pBorrowDelta_,
            uint256 p2pSupplyAmount_,
            uint256 p2pBorrowAmount_
        ) = lens.getMarketData(aDai);

        assertEq(p2pSupplyIndex, morpho.p2pSupplyIndex(aDai));
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(aDai));

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
            address underlying,
            bool isCreated,
            bool p2pDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint16 reserveFactor,
            uint16 p2pIndexCursor
        ) = lens.getMarketConfiguration(aDai);
        assertTrue(underlying == IAToken(aDai).UNDERLYING_ASSET_ADDRESS());

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

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
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

    function testGetIndexes() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
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
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = lens.getUpdatedP2PIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PIndexesWithBorrowDelta() public {
        _createBorrowDelta();
        hevm.warp(block.timestamp + 365 days);
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = lens.getUpdatedP2PIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PSupplyIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PSupplyIndex = lens.getUpdatedP2PSupplyIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PSupplyIndexWithDelta() public {
        _createSupplyDelta();
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PSupplyIndex = lens.getUpdatedP2PSupplyIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getUpdatedP2PBorrowIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
    }

    function testGetUpdatedP2PBorrowIndexWithDelta() public {
        _createBorrowDelta();
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getUpdatedP2PBorrowIndex(aDai);

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
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        borrower1.repay(aDai, type(uint256).max);
    }

    function _createBorrowDelta() public {
        uint256 amount = 1 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);
        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, amount / 2);
        borrower1.borrow(aDai, amount / 4);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(aDai, type(uint256).max);
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
        uint256 userMarketsBitmask = morpho.userMarkets(address(supplier1));

        uint256 j;
        for (uint256 i; i < pools.length; ) {
            address market = pools[i];

            for (j = 0; j < enteredMarkets.length; ) {
                if (enteredMarkets[j] == market) break;

                unchecked {
                    ++j;
                }
            }

            uint256 marketBitmask = morpho.borrowMask(market);
            if (userMarketsBitmask & (marketBitmask | (marketBitmask << 1)) != 0)
                assertLt(j, enteredMarkets.length, "market entered not in enteredMarkets");
            else assertEq(j, enteredMarkets.length, "market not entered in enteredMarkets");

            unchecked {
                ++i;
            }
        }
    }

    function testGetRatesPerYear() public {
        hevm.roll(block.number + 1_000);
        (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        ) = lens.getRatesPerYear(aDai);

        (uint256 expectedP2PSupplyRate, uint256 expectedP2PBorrowRate) = getApproxP2PRates(aDai);

        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(aDai).UNDERLYING_ASSET_ADDRESS()
        );
        uint256 expectedPoolSupplyRate = reserve.currentLiquidityRate;
        uint256 expectedPoolBorrowRate = reserve.currentVariableBorrowRate;

        assertEq(p2pSupplyRate, expectedP2PSupplyRate);
        assertEq(p2pBorrowRate, expectedP2PBorrowRate);
        assertEq(poolSupplyRate, expectedPoolSupplyRate);
        assertEq(poolBorrowRate, expectedPoolBorrowRate);
    }

    // function testIsLiquidatableFalse() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     assertFalse(lens.isLiquidatable(address(borrower1), new address[](0)));
    // }

    // function testIsLiquidatableTrue() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     createAndSetCustomPriceOracle().setDirectPrice(usdc, oracle.getUnderlyingPrice(aUsdc) / 2);

    //     assertTrue(lens.isLiquidatable(address(borrower1), new address[](0)));
    // }

    // function testComputeLiquidation() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     createAndSetCustomPriceOracle().setDirectPrice(usdc, 1);

    //     assertEq(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc, new address[](0)),
    //         0
    //     );
    // }

    // function testComputeLiquidation2() public {
    //     uint256 amount = 10_000 ether;

    //     borrower1.approve(usdc, to6Decimals(2 * amount));
    //     borrower1.supply(aUsdc, to6Decimals(2 * amount));
    //     borrower1.borrow(aDai, amount);

    //     assertEq(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc, new address[](0)),
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

    //     assertApproxEq(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc, new address[](0)),
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

    //     assertTrue(lens.isLiquidatable(address(borrower1), new address[](0)));

    //     assertApproxEq(
    //         lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc, new address[](0)),
    //         amount / 2,
    //         1
    //     );
    // }

    // function testLiquidationWithPoolIndexes() public {
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

    //     ICToken(aUsdc).accrueInterest();
    //     ICToken(aDai).accrueInterest();
    //     assertTrue(
    //         lens.isLiquidatable(address(borrower1), new address[](0)),
    //         "borrower is not liquidatable with updated pool indexes"
    //     );
    // }

    // function testLiquidatableWithP2PIndexes() public {
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

    //     morpho.updateIndexes(aUsdc);
    //     morpho.updateIndexes(aDai);
    //     assertTrue(
    //         lens.isLiquidatable(address(borrower1), new address[](0)),
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
    //         .getUserBalanceStates(address(borrower1), new address[](0));

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
    //         } while (lens.isLiquidatable(address(borrower1), new address[](0)) && toRepay > 0);

    //         // either the liquidatee's position (borrow value rayDivided by supply value) was under the [1 / liquidationIncentive] threshold and returned to a solvent position
    //         if (collateralValue.rayDiv(comptroller.liquidationIncentiveMantissa()) > debtValue) {
    //             assertFalse(lens.isLiquidatable(address(borrower1), new address[](0)));
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

    function testSupplyRateShouldEqual0WhenNoSupply() public {
        uint256 supplyRatePerYear = lens.getUserSupplyRatePerYear(aDai, address(supplier1));

        assertEq(supplyRatePerYear, 0);
    }

    function testBorrowRateShouldEqual0WhenNoBorrow() public {
        uint256 borrowRatePerYear = lens.getUserBorrowRatePerYear(aDai, address(borrower1));

        assertEq(borrowRatePerYear, 0);
    }

    function testUserSupplyRateShouldEqualPoolRateWhenNotMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        uint256 supplyRatePerYear = lens.getUserSupplyRatePerYear(aDai, address(supplier1));

        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(aDai).UNDERLYING_ASSET_ADDRESS()
        );
        assertApproxEq(supplyRatePerYear, reserve.currentLiquidityRate, 1);
    }

    function testUserBorrowRateShouldEqualPoolRateWhenNotMatched() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        uint256 borrowRatePerYear = lens.getUserBorrowRatePerYear(aDai, address(borrower1));

        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(aDai).UNDERLYING_ASSET_ADDRESS()
        );
        assertApproxEq(borrowRatePerYear, reserve.currentVariableBorrowRate, 1);
    }

    function testUserSupplyBorrowRatesShouldEqualP2PRatesWhenFullyMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wbtc, amount);
        supplier1.supply(aWbtc, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        uint256 supplyRatePerYear = lens.getUserSupplyRatePerYear(aDai, address(supplier1));
        uint256 borrowRatePerYear = lens.getUserBorrowRatePerYear(aDai, address(borrower1));
        (uint256 p2pSupplyRate, uint256 p2pBorrowRate, , ) = lens.getRatesPerYear(aDai);

        assertApproxEq(supplyRatePerYear, p2pSupplyRate, 1, "unexpected supply rate");
        assertApproxEq(borrowRatePerYear, p2pBorrowRate, 1, "unexpected borrow rate");
    }

    function testUserSupplyRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wbtc, amount);
        supplier1.supply(aWbtc, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount / 2);

        uint256 supplyRatePerYear = lens.getUserSupplyRatePerYear(aDai, address(supplier1));
        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerYear(aDai);

        assertApproxEq(supplyRatePerYear, (p2pSupplyRate + poolSupplyRate) / 2, 1e4);
    }

    function testUserBorrowRateShouldEqualMidrateWhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(wbtc, amount);
        supplier1.supply(aWbtc, amount);
        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);
        borrower1.borrow(aDai, amount);

        uint256 borrowRatePerYear = lens.getUserBorrowRatePerYear(aDai, address(borrower1));
        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerYear(aDai);

        assertApproxEq(borrowRatePerYear, (p2pBorrowRate + poolBorrowRate) / 2, 1e4);
    }

    function testSupplyRateShouldEqualPoolRateWithFullSupplyDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        morpho.setDefaultMaxGasForMatching(
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 0, repay: 0})
        );

        hevm.roll(block.number + 100);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (uint256 p2pSupplyRate, , uint256 poolSupplyRate, ) = lens.getRatesPerYear(aDai);

        assertApproxEq(p2pSupplyRate, poolSupplyRate, 1e4);
    }

    function testBorrowRateShouldEqualPoolRateWithFullBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        morpho.setDefaultMaxGasForMatching(
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 0, repay: 0})
        );

        hevm.roll(block.number + 100);

        supplier1.withdraw(aDai, type(uint256).max);

        (, uint256 p2pBorrowRate, , uint256 poolBorrowRate) = lens.getRatesPerYear(aDai);

        assertApproxEq(p2pBorrowRate, poolBorrowRate, 1e4);
    }

    function testNextSupplyRateShouldEqual0WhenNoSupply() public {
        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), 0);

        assertEq(supplyRatePerYear, 0, "non zero supply rate per block");
        assertEq(balanceOnPool, 0, "non zero pool balance");
        assertEq(balanceInP2P, 0, "non zero p2p balance");
        assertEq(totalBalance, 0, "non zero total balance");
    }

    function testNextBorrowRateShouldEqual0WhenNoBorrow() public {
        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(borrower1), 0);

        assertEq(borrowRatePerYear, 0, "non zero borrow rate per block");
        assertEq(balanceOnPool, 0, "non zero pool balance");
        assertEq(balanceInP2P, 0, "non zero p2p balance");
        assertEq(totalBalance, 0, "non zero total balance");
    }

    function testNextSupplyRateShouldEqualCurrentRateWhenNoNewSupply() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), 0);

        uint256 expectedSupplyRatePerYear = lens.getUserSupplyRatePerYear(aDai, address(supplier1));
        (
            uint256 expectedBalanceOnPool,
            uint256 expectedBalanceInP2P,
            uint256 expectedTotalBalance
        ) = lens.getUserSupplyBalance(address(supplier1), aDai);

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertEq(supplyRatePerYear, expectedSupplyRatePerYear, "unexpected supply rate per block");
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedTotalBalance, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualCurrentRateWhenNoNewBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(borrower1), 0);

        uint256 expectedBorrowRatePerYear = lens.getUserBorrowRatePerYear(aDai, address(borrower1));
        (
            uint256 expectedBalanceOnPool,
            uint256 expectedBalanceInP2P,
            uint256 expectedTotalBalance
        ) = lens.getUserBorrowBalance(address(borrower1), aDai);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertEq(borrowRatePerYear, expectedBorrowRatePerYear, "unexpected borrow rate per block");
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedTotalBalance, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualPoolRateWhenNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), amount);

        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(aDai).UNDERLYING_ASSET_ADDRESS()
        );
        uint256 expectedSupplyRatePerYear = reserve.currentLiquidityRate;
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEq(
            supplyRatePerYear,
            expectedSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
        );
        assertEq(
            balanceOnPool,
            amount.rayDiv(poolSupplyIndex).rayMul(poolSupplyIndex),
            "unexpected pool balance"
        );
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertEq(
            totalBalance,
            amount.rayDiv(poolSupplyIndex).rayMul(poolSupplyIndex),
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualPoolRateWhenNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(supplier1), amount);

        DataTypes.ReserveData memory reserve = pool.getReserveData(
            IAToken(aDai).UNDERLYING_ASSET_ADDRESS()
        );
        uint256 expectedBorrowRatePerYear = reserve.currentVariableBorrowRate;

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEq(
            borrowRatePerYear,
            expectedBorrowRatePerYear,
            1,
            "unexpected borrow rate per block"
        );
        assertApproxEq(balanceOnPool, amount, 1, "unexpected pool balance");
        assertEq(balanceInP2P, 0, "unexpected p2p balance");
        assertApproxEq(totalBalance, amount, 1, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWhenFullMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , , ) = lens.getRatesPerYear(aDai);

        morpho.updateIndexes(aDai);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        uint256 expectedBalanceInP2P = amount.rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEq(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWhenFullMatch() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        hevm.roll(block.number + 1000);

        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , ) = lens.getRatesPerYear(aDai);

        morpho.updateIndexes(aDai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        uint256 expectedBalanceInP2P = amount.rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEq(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1,
            "unexpected borrow rate per block"
        );
        assertApproxEq(balanceOnPool, 0, 1e6, "unexpected pool balance"); // compound rounding error at supply
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualMidrateWhenHalfMatch() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount / 2);

        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , uint256 poolSupplyRatePerYear, ) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        uint256 expectedBalanceOnPool = (amount / 2).rayDiv(poolSupplyIndex).rayMul(
            poolSupplyIndex
        );
        uint256 expectedBalanceInP2P = (amount / 2).rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEq(
            supplyRatePerYear,
            (p2pSupplyRatePerYear + poolSupplyRatePerYear) / 2,
            1e4,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualMidrateWhenHalfMatch() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount / 2);

        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , uint256 poolBorrowRatePerYear) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(dai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        uint256 expectedBalanceOnPool = (amount / 2).rayDiv(poolBorrowIndex).rayMul(
            poolBorrowIndex
        );
        uint256 expectedBalanceInP2P = (amount / 2).rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEq(
            borrowRatePerYear,
            (p2pBorrowRatePerYear + poolBorrowRatePerYear) / 2,
            1e4,
            "unexpected borrow rate per block"
        );
        assertApproxEq(balanceOnPool, expectedBalanceOnPool, 1e9, "unexpected pool balance");
        assertApproxEq(balanceInP2P, expectedBalanceInP2P, 1e9, "unexpected p2p balance");
        assertApproxEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            1e9,
            "unexpected total balance"
        );
    }

    function testNextSupplyRateShouldEqualP2PRateWhenDoubleSupply() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount / 2);

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), amount / 2);

        (uint256 p2pSupplyRatePerYear, , , ) = lens.getRatesPerYear(aDai);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEq(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertApproxEq(balanceInP2P, expectedBalanceInP2P, 1e9, "unexpected p2p balance");
        assertApproxEq(totalBalance, expectedBalanceInP2P, 1e9, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWhenDoubleBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(borrower1), amount / 2);

        (, uint256 p2pBorrowRatePerYear, , ) = lens.getRatesPerYear(aDai);

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEq(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1e4,
            "unexpected borrow rate per block"
        );
        assertApproxEq(balanceOnPool, 0, 1e6, "unexpected pool balance"); // compound rounding errors
        assertApproxEq(balanceInP2P, expectedBalanceInP2P, 1e9, "unexpected p2p balance");
        assertApproxEq(totalBalance, expectedBalanceInP2P, 1e9, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualP2PRateWithFullBorrowDeltaAndNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        morpho.setDefaultMaxGasForMatching(
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 0, repay: 0})
        );

        hevm.roll(block.number + 100);

        supplier1.withdraw(aDai, type(uint256).max);

        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , , ) = lens.getRatesPerYear(aDai);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEq(
            supplyRatePerYear,
            p2pSupplyRatePerYear,
            1,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextBorrowRateShouldEqualP2PRateWithFullSupplyDeltaAndNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        morpho.setDefaultMaxGasForMatching(
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 0, repay: 0})
        );

        hevm.roll(block.number + 100);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , ) = lens.getRatesPerYear(aDai);

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 expectedBalanceInP2P = amount.rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEq(
            borrowRatePerYear,
            p2pBorrowRatePerYear,
            1,
            "unexpected borrow rate per block"
        );
        assertEq(balanceOnPool, 0, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(totalBalance, expectedBalanceInP2P, "unexpected total balance");
    }

    function testNextSupplyRateShouldEqualMidrateWithHalfBorrowDeltaAndNoBorrowerOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount / 2);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);

        morpho.setDefaultMaxGasForMatching(
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 0, repay: 0})
        );

        hevm.roll(block.number + 1);

        supplier1.withdraw(aDai, type(uint256).max);

        uint256 daiBorrowdelta; // should be (amount / 2) but compound rounding leads to a slightly different amount which we need to compute
        {
            (, uint256 p2pBorrowDelta, , ) = morpho.deltas(aDai);
            daiBorrowdelta = p2pBorrowDelta.rayMul(pool.getReserveNormalizedVariableDebt(dai));
        }

        (
            uint256 supplyRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextSupplyRatePerYear(aDai, address(supplier1), amount);

        (uint256 p2pSupplyRatePerYear, , uint256 poolSupplyRatePerYear, ) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(dai);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);

        uint256 expectedBalanceOnPool = (amount - daiBorrowdelta).rayDiv(poolSupplyIndex).rayMul(
            poolSupplyIndex
        );
        uint256 expectedBalanceInP2P = daiBorrowdelta.rayDiv(p2pSupplyIndex).rayMul(p2pSupplyIndex);

        assertGt(supplyRatePerYear, 0, "zero supply rate per block");
        assertApproxEq(
            supplyRatePerYear,
            (p2pSupplyRatePerYear + poolSupplyRatePerYear) / 2,
            1e4,
            "unexpected supply rate per block"
        );
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            "unexpected total balance"
        );
    }

    function testNextBorrowRateShouldEqualMidrateWithHalfSupplyDeltaAndNoSupplierOnPool() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, amount);
        borrower1.supply(aWbtc, amount);
        borrower1.borrow(aDai, amount / 2);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);

        morpho.setDefaultMaxGasForMatching(
            Types.MaxGasForMatching({supply: 3e6, borrow: 3e6, withdraw: 0, repay: 0})
        );

        hevm.roll(block.number + 1);

        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        uint256 daiSupplydelta; // should be (amount / 2) but compound rounding leads to a slightly different amount which we need to compute
        {
            (uint256 p2pSupplyDelta, , , ) = morpho.deltas(aDai);
            daiSupplydelta = p2pSupplyDelta.rayMul(pool.getReserveNormalizedIncome(dai));
        }

        (
            uint256 borrowRatePerYear,
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        ) = lens.getNextBorrowRatePerYear(aDai, address(borrower1), amount);

        (, uint256 p2pBorrowRatePerYear, , uint256 poolBorrowRatePerYear) = lens.getRatesPerYear(
            aDai
        );

        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(dai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        uint256 expectedBalanceOnPool = (amount - daiSupplydelta).rayDiv(poolBorrowIndex).rayMul(
            poolBorrowIndex
        );
        uint256 expectedBalanceInP2P = daiSupplydelta.rayDiv(p2pBorrowIndex).rayMul(p2pBorrowIndex);

        assertGt(borrowRatePerYear, 0, "zero borrow rate per block");
        assertApproxEq(
            borrowRatePerYear,
            (p2pBorrowRatePerYear + poolBorrowRatePerYear) / 2,
            1e4,
            "unexpected borrow rate per block"
        );
        assertEq(balanceOnPool, expectedBalanceOnPool, "unexpected pool balance");
        assertEq(balanceInP2P, expectedBalanceInP2P, "unexpected p2p balance");
        assertEq(
            totalBalance,
            expectedBalanceOnPool + expectedBalanceInP2P,
            "unexpected total balance"
        );
    }
}
