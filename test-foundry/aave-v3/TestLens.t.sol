// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
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

        IConnector.ConfigParams memory config = connector.getConfigurationParams(dai);
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**config.reserveDecimals;

        assertEq(assetData.liquidationThreshold, config.liquidationThreshold);
        assertEq(assetData.ltv, config.ltv);
        assertEq(assetData.reserveDecimals, config.reserveDecimals);
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

        IConnector.ConfigParams memory config = connector.getConfigurationParams(dai);
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**config.reserveDecimals;
        uint256 collateralValue = (amount * underlyingPrice) / tokenUnit;

        assertEq(assetData.ltv, config.ltv, "ltv");
        assertEq(
            assetData.liquidationThreshold,
            config.liquidationThreshold,
            "liquidationThreshold"
        );
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

        IConnector.ConfigParams memory config = connector.getConfigurationParams(dai);
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**config.reserveDecimals;
        uint256 collateralValue = (amount * underlyingPrice) / tokenUnit;
        uint256 debtValue = (toBorrow * underlyingPrice) / tokenUnit;

        assertEq(
            assetData.liquidationThreshold,
            config.liquidationThreshold,
            "liquidationThreshold"
        );
        assertEq(assetData.ltv, config.ltv, "ltv");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.reserveDecimals, config.reserveDecimals, "reserveDecimals");
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

        IConnector.ConfigParams memory config = connector.getConfigurationParams(usdc);
        expectedDataUsdc.underlyingPrice = oracle.getAssetPrice(usdc);
        expectedDataUsdc.tokenUnit = 10**config.reserveDecimals;
        expectedDataUsdc.debtValue =
            (toBorrow * expectedDataUsdc.underlyingPrice) /
            expectedDataUsdc.tokenUnit;

        assertEq(
            assetDataUsdc.liquidationThreshold,
            config.liquidationThreshold,
            "liquidationThresholdUsdc"
        );
        assertEq(assetDataUsdc.ltv, config.ltv, "ltvUsdc");
        assertEq(
            assetDataUsdc.underlyingPrice,
            expectedDataUsdc.underlyingPrice,
            "underlyingPriceUsdc"
        );
        assertEq(assetDataUsdc.tokenUnit, expectedDataUsdc.tokenUnit, "tokenUnitUsdc");
        assertEq(assetDataUsdc.collateralValue, 0, "collateralValueUsdc");
        assertEq(assetDataUsdc.debtValue, expectedDataUsdc.debtValue, "debtValueUsdc");

        Types.AssetLiquidityData memory expectedDataDai;
        IConnector.ConfigParams memory config = connector.getConfigurationParams(dai);
        expectedDataDai.underlyingPrice = oracle.getAssetPrice(dai);
        expectedDataDai.tokenUnit = 10**config.reserveDecimals;
        expectedDataDai.collateralValue =
            (amount * expectedDataDai.underlyingPrice) /
            expectedDataDai.tokenUnit;

        assertEq(
            assetDataDai.liquidationThreshold,
            config.liquidationThreshold,
            "liquidationThresholdDai"
        );
        assertEq(assetDataDai.ltv, config.ltv, "ltvDai");
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

        testEquality(withdrawableUsdc, to6Decimals(amount), "withdrawableUsdc");
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
        IConnector.ConfigParams memory configUsdc = connector.getConfigurationParams(usdc);
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**configUsdc.reserveDecimals;

        // DAI data
        IConnector.ConfigParams memory configDai = connector.getConfigurationParams(dai);
        uint256 underlyingPriceDai = oracle.getAssetPrice(dai);
        uint256 tokenUnitDai = 10**configDai.reserveDecimals;

        expectedStates.collateralValue = (amount * underlyingPriceDai) / tokenUnitDai;
        expectedStates.debtValue = (toBorrow * underlyingPriceUsdc) / tokenUnitUsdc;
        expectedStates.liquidationThresholdValue = expectedStates.collateralValue.percentMul(
            configDai.liquidationThreshold
        );
        expectedStates.maxLoanToValue = expectedStates.collateralValue.percentMul(configDai.ltv);
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
        IConnector.ConfigParams memory config = connector.getConfigurationParams(usdc);
        uint256 collateralValueToAdd = (to6Decimals(amount) * oracle.getAssetPrice(usdc)) /
            10**config.reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.liquidationThresholdValue += collateralValueToAdd.percentMul(
            config.liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueToAdd.percentMul(configs.ltv);

        // DAI data
        config = pool.getConfigurationParams(dai);
        collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**configs.reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.liquidationThresholdValue += collateralValueToAdd.percentMul(
            config.liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueToAdd.percentMul(configs.ltv);

        // WBTC data
        config = pool.getConfigurationParams(wbtc);
        expectedStates.debtValue +=
            (toBorrowWbtc * oracle.getAssetPrice(wbtc)) /
            10**config.reserveDecimals;

        // USDT data
        config = pool.getConfigurationParams(usdt);
        expectedStates.debtValue +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) /
            10**config.reserveDecimals;

        expectedStates.healthFactor = expectedStates.liquidationThresholdValue.wadDiv(
            expectedStates.debtValue
        );

        assertApproxEq(
            states.collateralValue,
            expectedStates.collateralValue,
            1000,
            "collateralValue"
        );
        assertEq(states.debtValue, expectedStates.debtValue, "debtValue");
        assertApproxEq(
            states.liquidationThresholdValue,
            expectedStates.liquidationThresholdValue,
            1000,
            "liquidationThresholdValue"
        );
        assertApproxEq(
            states.maxLoanToValue,
            expectedStates.maxLoanToValue,
            1000,
            "maxLoanToValue"
        );
        testEqualityLarge(states.healthFactor, expectedStates.healthFactor, "healthFactor");
    }

    function testLiquidityDataWithMultipleAssets() public {
        // TODO: fix that.
        tip(usdt, address(morpho), 1);

        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(100 ether);

        tip(usdt, address(borrower1), to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.approve(usdt, to6Decimals(amount));
        borrower1.supply(aUsdt, to6Decimals(amount));

        borrower1.borrow(aUsdt, toBorrow);
        borrower1.borrow(aUsdc, toBorrow);

        uint256 reserveDecimals;
        uint256 ltv;
        uint256 liquidationThreshold;

        Types.LiquidityData memory expectedStates;
        Types.LiquidityData memory states = lens.getUserBalanceStates(address(borrower1));

        // USDT data
        IConnector.ConfigParams memory config = connector.getConfigurationParams(usdt);
        uint256 collateralValueUsdt = (to6Decimals(amount) * oracle.getAssetPrice(usdt)) /
            10**config.reserveDecimals;
        expectedStates.collateralValue += collateralValueUsdt;
        expectedStates.liquidationThresholdValue += collateralValueUsdt.percentMul(
            config.liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueUsdt.percentMul(config.ltv);

        // DAI data
        config = connector.getConfigurationParams(dai);
        uint256 collateralValueDai = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueDai;
        expectedStates.liquidationThresholdValue += collateralValueDai.percentMul(
            config.liquidationThreshold
        );
        expectedStates.maxLoanToValue += collateralValueDai.percentMul(config.ltv);

        // USDC data
        (, , , reserveDecimals, , ) = pool.getConfiguration(usdc).getParams();
        expectedStates.debtValue += (toBorrow * oracle.getAssetPrice(usdc)) / 10**reserveDecimals;

        // USDT data
        (, , , reserveDecimals, , ) = pool.getConfiguration(usdt).getParams();
        expectedStates.debtValue += (toBorrow * oracle.getAssetPrice(usdt)) / 10**reserveDecimals;

        expectedStates.healthFactor = expectedStates.liquidationThresholdValue.wadDiv(
            expectedStates.debtValue
        );

        testEqualityLarge(
            states.collateralValue,
            expectedStates.collateralValue,
            "collateralValue"
        );
        assertEq(states.debtValue, expectedStates.debtValue, "debtValue");
        testEqualityLarge(
            states.liquidationThresholdValue,
            expectedStates.liquidationThresholdValue,
            "liquidationThresholdValue"
        );
        testEqualityLarge(states.maxLoanToValue, expectedStates.maxLoanToValue, "maxLoanToValue");
        testEqualityLarge(states.healthFactor, expectedStates.healthFactor, "healthFactor");
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
        return
            (morpho.userMarketsBitmask(_user) >> ((morpho.indexOfMarket(_market) << 1) + 1)) & 1 !=
            0;
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

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getUpdatedP2PBorrowIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
    }
}
