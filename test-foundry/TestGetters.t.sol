// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestGetters is TestSetup {
    struct AssetLiquidityData {
        uint256 collateralValueToAdd;
        uint256 maxDebtValueToAdd;
        uint256 debtValueToAdd;
        uint256 tokenUnit;
        uint256 underlyingPrice;
        uint256 liquidationThreshold;
    }

    function test_user_liquidity_data_for_asset_with_nothing() public {
        PositionsManagerForAave.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        (
            uint256 reserveDecimals,
            ,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(dai);
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**reserveDecimals;

        assertEq(assetData.liquidationThreshold, liquidationThreshold);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.tokenUnit, tokenUnit);
        assertEq(assetData.collateralValue, 0);
        assertEq(assetData.maxDebtValue, 0);
        assertEq(assetData.debtValue, 0);
    }

    function test_user_liquidity_data_for_asset_with_supply() public {
        uint256 amount = 10000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        PositionsManagerForAave.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        (
            uint256 reserveDecimals,
            ,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(dai);
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**reserveDecimals;
        uint256 collateralValue = (amount * underlyingPrice) / tokenUnit;
        uint256 maxDebtValue = (collateralValue * liquidationThreshold) / MAX_BASIS_POINTS;

        assertEq(assetData.liquidationThreshold, liquidationThreshold);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.tokenUnit, tokenUnit);
        assertEq(assetData.collateralValue, collateralValue);
        assertEq(assetData.maxDebtValue, maxDebtValue);
        assertEq(assetData.debtValue, 0);
    }

    function test_user_liquidity_data_for_asset_with_supply_and_borrow() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = amount / 2;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aDai, toBorrow);

        PositionsManagerForAave.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        (
            uint256 reserveDecimals,
            ,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(dai);
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**reserveDecimals;
        uint256 collateralValue = (amount * underlyingPrice) / tokenUnit;
        uint256 maxDebtValue = (collateralValue * liquidationThreshold) / MAX_BASIS_POINTS;
        uint256 debtValue = (toBorrow * underlyingPrice) / tokenUnit;

        assertEq(assetData.liquidationThreshold, liquidationThreshold);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.tokenUnit, tokenUnit);
        assertEq(assetData.collateralValue, collateralValue);
        assertEq(assetData.maxDebtValue, maxDebtValue);
        assertEq(assetData.debtValue, debtValue);
    }

    function test_user_liquidity_data_for_asset_with_supply_and_borrow_with_different_assets()
        public
    {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        PositionsManagerForAave.AssetLiquidityData memory assetDataDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        PositionsManagerForAave.AssetLiquidityData memory assetDataUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aUsdc, oracle);

        (
            uint256 reserveDecimalsUsdc,
            ,
            uint256 liquidationThresholdUsdc,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(usdc);
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**reserveDecimalsUsdc;
        uint256 debtValueUsdc = (toBorrow * underlyingPriceUsdc) / tokenUnitUsdc;

        assertEq(assetDataUsdc.liquidationThreshold, liquidationThresholdUsdc);
        assertEq(assetDataUsdc.underlyingPrice, underlyingPriceUsdc);
        assertEq(assetDataUsdc.tokenUnit, tokenUnitUsdc);
        assertEq(assetDataUsdc.collateralValue, 0);
        assertEq(assetDataUsdc.maxDebtValue, 0);
        assertEq(assetDataUsdc.debtValue, debtValueUsdc);

        (
            uint256 reserveDecimalsDai,
            ,
            uint256 liquidationThresholdDai,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(dai);
        uint256 underlyingPriceDai = oracle.getAssetPrice(dai);
        uint256 tokenUnitDai = 10**reserveDecimalsDai;
        uint256 collateralValueDai = (amount * underlyingPriceDai) / tokenUnitDai;
        uint256 maxDebtValueDai = (collateralValueDai * liquidationThresholdDai) / MAX_BASIS_POINTS;

        assertEq(assetDataDai.liquidationThreshold, liquidationThresholdDai);
        assertEq(assetDataDai.underlyingPrice, underlyingPriceDai);
        assertEq(assetDataDai.tokenUnit, tokenUnitDai);
        assertEq(assetDataDai.collateralValue, collateralValueDai);
        assertEq(assetDataDai.maxDebtValue, maxDebtValueDai);
        assertEq(assetDataDai.debtValue, 0);
    }

    function test_getter_user_with_nothing() public {
        (uint256 withdrawable, uint256 borrowable) = positionsManager.getAssetMaxCapacities(
            address(borrower1),
            aDai
        );

        assertEq(withdrawable, 0);
        assertEq(borrowable, 0);
    }

    function test_asset_max_capacities_with_supply_on_one_asset() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));

        PositionsManagerForAave.AssetLiquidityData memory assetDataUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aUsdc, oracle);

        PositionsManagerForAave.AssetLiquidityData memory assetDataDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        uint256 expectedBorrowable = (assetDataUsdc.maxDebtValue * assetDataDai.tokenUnit) /
            assetDataDai.underlyingPrice;

        (uint256 withdrawable, ) = positionsManager.getAssetMaxCapacities(
            address(borrower1),
            aUsdc
        );

        (, uint256 borrowable) = positionsManager.getAssetMaxCapacities(address(borrower1), aDai);

        assertEq(withdrawable, to6Decimals(amount));
        assertEq(borrowable, expectedBorrowable);
    }

    function test_asset_max_capacities_with_supply_on_several_assets_and_borrow() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        PositionsManagerForAave.AssetLiquidityData memory assetDataUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aUsdc, oracle);

        PositionsManagerForAave.AssetLiquidityData memory assetDataDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        PositionsManagerForAave.AssetLiquidityData memory assetDataWmatic = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aWmatic, oracle);

        (uint256 withdrawableDai, ) = positionsManager.getAssetMaxCapacities(
            address(borrower1),
            aDai
        );

        (uint256 withdrawableUsdc, ) = positionsManager.getAssetMaxCapacities(
            address(borrower1),
            aUsdc
        );

        (, uint256 borrowableWmatic) = positionsManager.getAssetMaxCapacities(
            address(borrower1),
            aWmatic
        );

        uint256 expectedBorrowable = ((assetDataUsdc.maxDebtValue + assetDataDai.maxDebtValue) *
            assetDataWmatic.tokenUnit) / assetDataWmatic.underlyingPrice;

        assertEq(withdrawableUsdc, to6Decimals(amount));
        assertEq(withdrawableDai, amount);
        assertEq(borrowableWmatic, expectedBorrowable);

        uint256 toBorrow = 100 ether;
        borrower1.borrow(aWmatic, toBorrow);

        (, uint256 newBorrowableWmatic) = positionsManager.getAssetMaxCapacities(
            address(borrower1),
            aWmatic
        );

        expectedBorrowable -= toBorrow;

        assertEq(newBorrowableWmatic, expectedBorrowable);
    }
}
