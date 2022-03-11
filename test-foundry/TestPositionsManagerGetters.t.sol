// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./utils/TestSetup.sol";

contract TestPositionsManagerGetters is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

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

        uint8 NDS = 10;
        positionsManager.setNDS(NDS);
        createSigners(NDS);
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
            mineBlocks(1);
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, , ) = pool
        .getConfiguration(dai)
        .getParams();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**reserveDecimals;

        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertEq(assetData.collateralValue, 0, "collateralValue");
        assertEq(assetData.maxDebtValue, 0, "maxDebtValue");
        assertEq(assetData.debtValue, 0, "debtValue");
    }

    function test_user_liquidity_data_for_asset_with_supply() public {
        uint256 amount = 10000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        PositionsManagerForAave.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aDai, oracle);

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, , ) = pool
        .getConfiguration(dai)
        .getParams();
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 reserveDecimals, , ) = pool
        .getConfiguration(dai)
        .getParams();
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
            expectedDataUsdc.ltv,
            expectedDataUsdc.liquidationThreshold,
            ,
            reserveDecimalsUsdc,
            ,

        ) = pool.getConfiguration(usdc).getParams();
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

        (expectedDataDai.ltv, expectedDataDai.liquidationThreshold, , reserveDecimalsDai, , ) = pool
        .getConfiguration(dai)
        .getParams();
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

        uint256 expectedBorrowableUsdc = (assetDataUsdc.maxDebtValue * assetDataUsdc.tokenUnit) /
            assetDataUsdc.underlyingPrice;
        uint256 expectedBorrowableDai = (assetDataUsdc.maxDebtValue * assetDataDai.tokenUnit) /
            assetDataDai.underlyingPrice;

        (uint256 withdrawable, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );

        assertEq(withdrawable, to6Decimals(amount), "withdrawable USDC");
        assertEq(borrowable, expectedBorrowableUsdc, "borrowable USDC");

        (withdrawable, borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
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

        PositionsManagerForAave.AssetLiquidityData memory assetDataUsdt = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), aUsdt, oracle);

        (uint256 withdrawableDai, ) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

        (uint256 withdrawableUsdc, ) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );

        (, uint256 borrowableUsdt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdt
        );

        uint256 expectedBorrowable = ((assetDataUsdc.maxDebtValue + assetDataDai.maxDebtValue) *
            assetDataUsdt.tokenUnit) / assetDataUsdt.underlyingPrice;

        assertEq(withdrawableUsdc, to6Decimals(amount));
        assertEq(withdrawableDai, amount);
        assertEq(borrowableUsdt, expectedBorrowable);

        uint256 toBorrow = to6Decimals(100 ether);
        borrower1.borrow(aUsdt, toBorrow);

        (, uint256 newBorrowableUsdt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdt
        );

        expectedBorrowable -= toBorrow;

        assertEq(newBorrowableUsdt, expectedBorrowable);
    }

    function test_user_balance_states_with_supply_and_borrow() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (
            states.collateralValue,
            states.debtValue,
            states.maxDebtValue,
            states.liquidationValue
        ) = positionsManager.getUserBalanceStates(address(borrower1));

        // USDC data
        (, , , uint256 reserveDecimalsUsdc, , ) = pool.getConfiguration(usdc).getParams();
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**reserveDecimalsUsdc;

        // DAI data
        (uint256 ltvDai, uint256 liquidationThresholdDai, , uint256 reserveDecimalsDai, , ) = pool
        .getConfiguration(dai)
        .getParams();
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

    function test_user_balance_states_with_supply_and_borrow_on_several_assets() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 100 ether;
        uint256 toBorrowWbtc = to6Decimals(0.001 ether);

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        borrower1.borrow(aWbtc, toBorrowWbtc);
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
        (ltv, liquidationThreshold, , reserveDecimals, , ) = pool
        .getConfiguration(usdc)
        .getParams();
        uint256 collateralValueToAdd = (to6Decimals(amount) * oracle.getAssetPrice(usdc)) /
            10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += (collateralValueToAdd * ltv) / MAX_BASIS_POINTS;
        expectedStates.liquidationValue +=
            (collateralValueToAdd * liquidationThreshold) /
            MAX_BASIS_POINTS;

        // DAI data
        (ltv, liquidationThreshold, , reserveDecimals, , ) = pool.getConfiguration(dai).getParams();
        collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += (collateralValueToAdd * ltv) / MAX_BASIS_POINTS;
        expectedStates.liquidationValue +=
            (collateralValueToAdd * liquidationThreshold) /
            MAX_BASIS_POINTS;

        // WBTC data
        (, , , reserveDecimals, , ) = pool.getConfiguration(wbtc).getParams();
        expectedStates.debtValue +=
            (toBorrowWbtc * oracle.getAssetPrice(wbtc)) /
            10**reserveDecimals;

        // USDT data
        (, , , reserveDecimals, , ) = pool.getConfiguration(usdt).getParams();
        expectedStates.debtValue +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) /
            10**reserveDecimals;

        assertEq(states.collateralValue, expectedStates.collateralValue);
        assertEq(states.debtValue, expectedStates.debtValue);
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue);
        assertEq(states.liquidationValue, expectedStates.liquidationValue);
    }

    function test_get_user_liquidity_data_with_differents_assets_and_usdt() public {
        uint256 amount = 100 ether;
        uint256 toBorrow = 10 ether;

        writeBalanceOf(address(borrower1), usdt, to6Decimals(amount));
        borrower1.approve(usdt, to6Decimals(amount));
        borrower1.supply(aUsdt, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        borrower1.borrow(aUsdc, to6Decimals(toBorrow));
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

        // USDT data
        (ltv, liquidationThreshold, , reserveDecimals, , ) = pool
        .getConfiguration(usdt)
        .getParams();

        // DAI data
        (ltv, liquidationThreshold, , reserveDecimals, , ) = pool.getConfiguration(dai).getParams();
        uint256 collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**reserveDecimals;
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += (collateralValueToAdd * ltv) / MAX_BASIS_POINTS;
        expectedStates.liquidationValue +=
            (collateralValueToAdd * liquidationThreshold) /
            MAX_BASIS_POINTS;

        // USDC data
        (, , , reserveDecimals, , ) = pool.getConfiguration(usdc).getParams();
        expectedStates.debtValue +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdc)) /
            10**reserveDecimals;

        // USDT data
        (, , , reserveDecimals, , ) = pool.getConfiguration(usdt).getParams();
        expectedStates.debtValue +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) /
            10**reserveDecimals;

        assertEq(states.collateralValue, expectedStates.collateralValue, "collateralValue");
        assertEq(states.debtValue, expectedStates.debtValue, "debtValue");
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue, "maxDebtValue");
        assertEq(states.liquidationValue, expectedStates.liquidationValue, "liquidationValue");
    }
}
