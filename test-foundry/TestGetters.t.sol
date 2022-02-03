// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./utils/TestSetup.sol";

contract TestGetters is TestSetup {
    struct UserBalanceStates {
        uint256 collateralValue;
        uint256 debtValue;
        uint256 maxDebtValue;
        uint256 liquidationValue;
    }

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    function test_get_head() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = amount / 10;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        assertEq(
            address(0),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.SUPPLIERS_IN_P2P)
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.SUPPLIERS_ON_POOL)
        );
        assertEq(
            address(0),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.BORROWERS_IN_P2P)
        );
        assertEq(
            address(0),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.BORROWERS_ON_POOL)
        );

        borrower1.borrow(aDai, toBorrow);

        assertEq(
            address(borrower1),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.SUPPLIERS_IN_P2P)
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.SUPPLIERS_ON_POOL)
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.BORROWERS_IN_P2P)
        );
        assertEq(
            address(0),
            positionsManager.getHead(aDai, PositionsManagerForAave.PositionType.BORROWERS_ON_POOL)
        );

        borrower1.borrow(aUsdc, to6Decimals(toBorrow));

        assertEq(
            address(borrower1),
            positionsManager.getHead(aUsdc, PositionsManagerForAave.PositionType.BORROWERS_ON_POOL)
        );
    }

    function test_get_next() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 10);

        setNMAXAndCreateSigners(10);
        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].approve(dai, amount - i);
            borrowers[i].supply(aDai, amount - i);
            borrowers[i].borrow(aUsdc, toBorrow - i);
        }

        address nextSupplyOnPool = address(borrowers[0]);
        address nextBorrowOnPool = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyOnPool = positionsManager.getNext(
                aDai,
                PositionsManagerForAave.PositionType.SUPPLIERS_ON_POOL,
                nextSupplyOnPool
            );
            nextBorrowOnPool = positionsManager.getNext(
                aUsdc,
                PositionsManagerForAave.PositionType.BORROWERS_ON_POOL,
                nextBorrowOnPool
            );

            assertEq(nextSupplyOnPool, address(borrowers[i + 1]));
            assertEq(nextBorrowOnPool, address(borrowers[i + 1]));
        }

        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].borrow(aDai, (amount / 100) - i);
        }

        for (uint256 i; i < suppliers.length; i++) {
            suppliers[i].approve(usdc, toBorrow - i);
            suppliers[i].supply(aUsdc, toBorrow - i);
        }

        address nextSupplyInP2P = address(suppliers[0]);
        address nextBorrowInP2P = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyInP2P = positionsManager.getNext(
                aUsdc,
                PositionsManagerForAave.PositionType.SUPPLIERS_IN_P2P,
                nextSupplyInP2P
            );
            nextBorrowInP2P = positionsManager.getNext(
                aDai,
                PositionsManagerForAave.PositionType.BORROWERS_IN_P2P,
                nextBorrowInP2P
            );

            assertEq(address(suppliers[i + 1]), nextSupplyInP2P);
            assertEq(address(borrowers[i + 1]), nextBorrowInP2P);
        }
    }

    function test_user_liquidity_data_for_asset_with_nothing() public {
        PositionsManagerForAave.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        (
            uint256 reserveDecimals,
            uint256 ltv,
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
        assertEq(assetData.ltv, ltv);
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
            uint256 ltv,
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
        uint256 maxDebtValue = (collateralValue * ltv) / MAX_BASIS_POINTS;
        uint256 liquidationValue = (collateralValue * liquidationThreshold) / MAX_BASIS_POINTS;

        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertEq(assetData.collateralValue, collateralValue, "collateralValue");
        assertEq(assetData.maxDebtValue, maxDebtValue, "maxDebtValue");
        assertEq(assetData.liquidationValue, liquidationValue, "liquidationValue");
        assertEq(assetData.debtValue, 0, "debtValue");
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
            uint256 ltv,
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
        uint256 liquidationValue = (collateralValue * liquidationThreshold) / MAX_BASIS_POINTS;
        uint256 maxDebtValue = (collateralValue * ltv) / MAX_BASIS_POINTS;
        uint256 debtValue = (toBorrow * underlyingPrice) / tokenUnit;

        testEquality(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        testEquality(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        testEquality(assetData.tokenUnit, tokenUnit, "tokenUnit");
        testEquality(assetData.collateralValue, collateralValue, "collateralValue");
        testEquality(assetData.liquidationValue, liquidationValue, "liquidationValue");
        testEquality(assetData.maxDebtValue, maxDebtValue, "maxDebtValue");
        testEquality(assetData.debtValue, debtValue, "debtValue");
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

        // Avoid stack too deep error
        PositionsManagerForAave.AssetLiquidityData memory expectedDataUsdc;
        uint256 reserveDecimalsUsdc;

        (
            reserveDecimalsUsdc,
            expectedDataUsdc.ltv,
            expectedDataUsdc.liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(usdc);
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
        assertEq(assetDataUsdc.collateralValue, 0, "collateralValue");
        assertEq(assetDataUsdc.maxDebtValue, 0, "maxDebtValue");
        assertEq(assetDataUsdc.debtValue, expectedDataUsdc.debtValue, "debtValueUsdc");

        // Avoid stack too deep error
        PositionsManagerForAave.AssetLiquidityData memory expectedDataDai;
        uint256 reserveDecimalsDai;

        (
            reserveDecimalsDai,
            expectedDataDai.ltv,
            expectedDataDai.liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(dai);
        expectedDataDai.underlyingPrice = oracle.getAssetPrice(dai);
        expectedDataDai.tokenUnit = 10**reserveDecimalsDai;
        expectedDataDai.collateralValue =
            (amount * expectedDataDai.underlyingPrice) /
            expectedDataDai.tokenUnit;
        expectedDataDai.maxDebtValue =
            (expectedDataDai.collateralValue * expectedDataDai.ltv) /
            MAX_BASIS_POINTS;

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
        assertEq(assetDataDai.maxDebtValue, expectedDataDai.maxDebtValue, "maxDebtValueDai");
        assertEq(assetDataDai.debtValue, 0, "debtValueDai");
    }

    function test_getter_user_with_nothing() public {
        (uint256 withdrawable, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
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

        (uint256 withdrawable, ) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

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

        (uint256 withdrawableDai, ) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

        (uint256 withdrawableUsdc, ) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );

        (, uint256 borrowableWmatic) = positionsManager.getUserMaxCapacitiesForAsset(
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

        (, uint256 newBorrowableWmatic) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aWmatic
        );

        expectedBorrowable -= toBorrow;

        assertEq(newBorrowableWmatic, expectedBorrowable);
    }

    function test_user_balance_states_with_supply_and_borrow() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        // Avoid stack too deep error
        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (
            states.collateralValue,
            states.debtValue,
            states.maxDebtValue,
            states.liquidationValue
        ) = positionsManager.getUserBalanceStates(address(borrower1));

        // USDC data
        (uint256 reserveDecimalsUsdc, , , , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(usdc);
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**reserveDecimalsUsdc;

        // DAI data
        (
            uint256 reserveDecimalsDai,
            uint256 ltvDai,
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
        expectedStates.collateralValue = (amount * underlyingPriceDai) / tokenUnitDai;

        expectedStates.debtValue = (toBorrow * underlyingPriceUsdc) / tokenUnitUsdc;
        expectedStates.maxDebtValue = (expectedStates.collateralValue * ltvDai) / MAX_BASIS_POINTS;
        expectedStates.liquidationValue =
            (expectedStates.collateralValue * liquidationThresholdDai) /
            MAX_BASIS_POINTS;

        assertEq(states.collateralValue, expectedStates.collateralValue);
        assertEq(states.liquidationValue, expectedStates.liquidationValue);
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue);
        assertEq(states.debtValue, expectedStates.debtValue);
    }

    function test_user_balance_states_with_supply_and_borrow_on_several_borrow() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 100 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        borrower1.borrow(aWmatic, toBorrow);
        borrower1.borrow(aUsdt, to6Decimals(toBorrow));

        uint256 reserveDecimals;
        uint256 ltv;
        uint256 liquidationThreshold;

        // Avoid stack too deep error
        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (
            states.collateralValue,
            states.debtValue,
            states.maxDebtValue,
            states.liquidationValue
        ) = positionsManager.getUserBalanceStates(address(borrower1));

        // USDC data
        (reserveDecimals, ltv, liquidationThreshold, , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(usdc);
        uint256 collateralValueToAdd = (to6Decimals(amount) * oracle.getAssetPrice(usdc)) /
            10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += (collateralValueToAdd * ltv) / MAX_BASIS_POINTS;
        expectedStates.liquidationValue +=
            (collateralValueToAdd * liquidationThreshold) /
            MAX_BASIS_POINTS;

        // DAI data
        (reserveDecimals, ltv, liquidationThreshold, , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(dai);
        collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += (collateralValueToAdd * ltv) / MAX_BASIS_POINTS;
        expectedStates.liquidationValue +=
            (collateralValueToAdd * liquidationThreshold) /
            MAX_BASIS_POINTS;

        // WMATIC data
        (reserveDecimals, , , , , , , , , ) = protocolDataProvider.getReserveConfigurationData(
            wmatic
        );
        expectedStates.debtValue += (toBorrow * oracle.getAssetPrice(wmatic)) / 10**reserveDecimals;

        // USDT data
        (reserveDecimals, , , , , , , , , ) = protocolDataProvider.getReserveConfigurationData(
            usdt
        );
        expectedStates.debtValue +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) /
            10**reserveDecimals;

        assertEq(states.collateralValue, expectedStates.collateralValue);
        assertEq(states.debtValue, expectedStates.debtValue);
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue);
        assertEq(states.liquidationValue, expectedStates.liquidationValue);
    }
}
