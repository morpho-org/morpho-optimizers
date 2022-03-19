// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";

contract TestPositionsManagerGetters is TestSetup {
    using CompoundMath for uint256;

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
        borrower1.supply(cDai, amount);

        assertEq(
            address(0),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.SUPPLIERS_IN_P2P
            )
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.SUPPLIERS_ON_POOL
            )
        );
        assertEq(
            address(0),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.BORROWERS_IN_P2P
            )
        );
        assertEq(
            address(0),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.BORROWERS_ON_POOL
            )
        );

        borrower1.borrow(cDai, toBorrow);

        assertEq(
            address(borrower1),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.SUPPLIERS_IN_P2P
            )
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.SUPPLIERS_ON_POOL
            )
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.BORROWERS_IN_P2P
            )
        );
        assertEq(
            address(0),
            positionsManager.getHead(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.BORROWERS_ON_POOL
            )
        );

        borrower1.borrow(cUsdc, to6Decimals(toBorrow));

        assertEq(
            address(borrower1),
            positionsManager.getHead(
                cUsdc,
                PositionsManagerForCompoundStorage.PositionType.BORROWERS_ON_POOL
            )
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
            borrowers[i].supply(cDai, amount - i);
            borrowers[i].borrow(cUsdc, toBorrow - i);
        }

        address nextSupplyOnPool = address(borrowers[0]);
        address nextBorrowOnPool = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyOnPool = positionsManager.getNext(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.SUPPLIERS_ON_POOL,
                nextSupplyOnPool
            );
            nextBorrowOnPool = positionsManager.getNext(
                cUsdc,
                PositionsManagerForCompoundStorage.PositionType.BORROWERS_ON_POOL,
                nextBorrowOnPool
            );

            assertEq(nextSupplyOnPool, address(borrowers[i + 1]));
            assertEq(nextBorrowOnPool, address(borrowers[i + 1]));
        }

        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].borrow(cDai, (amount / 100) - i);
        }

        for (uint256 i; i < suppliers.length; i++) {
            suppliers[i].approve(usdc, toBorrow - i);
            suppliers[i].supply(cUsdc, toBorrow - i);
        }

        address nextSupplyInP2P = address(suppliers[0]);
        address nextBorrowInP2P = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyInP2P = positionsManager.getNext(
                cUsdc,
                PositionsManagerForCompoundStorage.PositionType.SUPPLIERS_IN_P2P,
                nextSupplyInP2P
            );
            nextBorrowInP2P = positionsManager.getNext(
                cDai,
                PositionsManagerForCompoundStorage.PositionType.BORROWERS_IN_P2P,
                nextBorrowInP2P
            );

            assertEq(address(suppliers[i + 1]), nextSupplyInP2P);
            assertEq(address(borrowers[i + 1]), nextBorrowInP2P);
        }
    }

    function test_user_liquidity_data_for_asset_with_nothing() public {
        PositionsManagerForCompound.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        assertEq(assetData.collateralFactor, collateralFactor);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.collateralValue, 0);
        assertEq(assetData.maxDebtValue, 0);
        assertEq(assetData.debtValue, 0);
    }

    function test_user_liquidity_data_for_asset_with_supply() public {
        uint256 amount = 10000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        PositionsManagerForCompound.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        uint256 collateralValue = amount.mul(underlyingPrice);
        uint256 maxDebtValue = collateralValue.mul(collateralFactor);

        testEquality(assetData.collateralFactor, collateralFactor, "collateralFactor");
        testEquality(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        testEquality(assetData.collateralValue, collateralValue, "collateralValue");
        testEquality(assetData.maxDebtValue, maxDebtValue, "maxDebtValue");
        assertEq(assetData.debtValue, 0, "debtValue");
    }

    function test_user_liquidity_data_for_asset_with_supply_and_borrow() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = amount / 2;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cDai, toBorrow);

        PositionsManagerForCompound.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        uint256 collateralValue = amount.mul(underlyingPrice);
        uint256 maxDebtValue = collateralValue.mul(collateralFactor);
        uint256 debtValue = toBorrow.mul(underlyingPrice);

        testEquality(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        testEquality(assetData.collateralValue, collateralValue, "collateralValue");
        testEquality(assetData.maxDebtValue, maxDebtValue, "maxDebtValue");
        testEquality(assetData.debtValue, debtValue, "debtValue");
    }

    function test_user_liquidity_data_for_asset_with_supply_and_borrow_with_different_assets()
        public
    {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        PositionsManagerForCompound.AssetLiquidityData memory assetDatacDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        PositionsManagerForCompound.AssetLiquidityData memory assetDatcUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cUsdc, oracle);

        // Avoid stack too deep error
        PositionsManagerForCompound.AssetLiquidityData memory expectedDatcUsdc;
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);
        expectedDatcUsdc.underlyingPrice = oracle.getUnderlyingPrice(cUsdc);

        expectedDatcUsdc.debtValue = toBorrow.mul(expectedDatcUsdc.underlyingPrice);

        testEquality(
            assetDatcUsdc.underlyingPrice,
            expectedDatcUsdc.underlyingPrice,
            "underlyingPriceUsdc"
        );
        testEquality(assetDatcUsdc.collateralValue, 0, "collateralValue");
        testEquality(assetDatcUsdc.maxDebtValue, 0, "maxDebtValue");
        testEquality(assetDatcUsdc.debtValue, expectedDatcUsdc.debtValue, "debtValueUsdc");

        // Avoid stack too deep error
        PositionsManagerForCompound.AssetLiquidityData memory expectedDatacDai;

        (, collateralFactor, ) = comptroller.markets(cDai);

        expectedDatacDai.underlyingPrice = oracle.getUnderlyingPrice(cDai);
        expectedDatacDai.collateralValue = amount.mul(expectedDatacDai.underlyingPrice);
        expectedDatacDai.maxDebtValue = expectedDatacDai.collateralValue.mul(
            expectedDatacDai.collateralFactor
        );

        testEquality(assetDatacDai.collateralFactor, collateralFactor, "collateralFactor");
        testEquality(
            assetDatacDai.underlyingPrice,
            expectedDatacDai.underlyingPrice,
            "underlyingPriceDai"
        );

        testEquality(
            assetDatacDai.collateralValue,
            expectedDatacDai.collateralValue,
            "collateralValueDai"
        );
        testEquality(assetDatacDai.maxDebtValue, expectedDatacDai.maxDebtValue, "maxDebtValueDai");
        assertEq(assetDatacDai.debtValue, 0, "debtValueDai");
    }

    function test_getter_user_with_nothing() public {
        (uint256 withdrawable, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        assertEq(withdrawable, 0);
        assertEq(borrowable, 0);
    }

    function test_asset_max_capacities_with_supply_on_one_asset() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));

        PositionsManagerForCompound.AssetLiquidityData memory assetDatcUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cUsdc, oracle);

        PositionsManagerForCompound.AssetLiquidityData memory assetDatacDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        uint256 expectedBorrowableUsdc = assetDatcUsdc.maxDebtValue.div(
            assetDatcUsdc.underlyingPrice
        );
        uint256 expectedBorrowableDai = assetDatcUsdc.maxDebtValue.div(
            assetDatacDai.underlyingPrice
        );

        (uint256 withdrawable, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdc
        );

        testEquality(withdrawable, to6Decimals(amount), "withdrawable USDC");
        assertEq(borrowable, expectedBorrowableUsdc, "borrowable USDC");

        (withdrawable, borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
    }

    function test_asset_max_capacities_with_supply_on_several_assets_and_borrow() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        PositionsManagerForCompound.AssetLiquidityData memory assetDatcUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cUsdc, oracle);

        PositionsManagerForCompound.AssetLiquidityData memory assetDatacDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        PositionsManagerForCompound.AssetLiquidityData memory assetDatacUsdt = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cUsdt, oracle);

        (uint256 withdrawableDai, ) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        (uint256 withdrawableUsdc, ) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdc
        );

        (, uint256 borrowableUsdt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdt
        );

        uint256 expectedBorrowableUsdt = (assetDatacDai.maxDebtValue * assetDatcUsdc.maxDebtValue)
        .div(assetDatacUsdt.underlyingPrice);

        assertEq(withdrawableUsdc, to6Decimals(amount));
        assertEq(withdrawableDai, amount);
        assertEq(borrowableUsdt, expectedBorrowableUsdt);

        uint256 toBorrow = to6Decimals(100 ether);
        borrower1.borrow(cUsdt, toBorrow);

        (, uint256 newBorrowableUsdt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdt
        );

        expectedBorrowableUsdt -= toBorrow;

        assertEq(newBorrowableUsdt, expectedBorrowableUsdt);
    }

    function test_user_balance_states_with_supply_and_borrow() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (states.collateralValue, states.debtValue, states.maxDebtValue) = positionsManager
        .getUserBalanceStates(address(borrower1));

        uint256 underlyingPriceUsdc = oracle.getUnderlyingPrice(cUsdc);

        // DAI data
        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPriceDai = oracle.getUnderlyingPrice(cDai);
        expectedStates.collateralValue = amount.mul(underlyingPriceDai);

        expectedStates.debtValue = toBorrow.mul(underlyingPriceUsdc);
        expectedStates.maxDebtValue = expectedStates.collateralValue.mul(collateralFactor);

        testEquality(states.collateralValue, expectedStates.collateralValue);
        testEquality(states.maxDebtValue, expectedStates.maxDebtValue);
        testEquality(states.debtValue, expectedStates.debtValue);
    }

    function test_user_balance_states_with_supply_and_borrow_on_several_assets() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 100 ether;
        uint256 toBorrowWbtc = to6Decimals(0.001 ether);

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        borrower1.borrow(cWbtc, toBorrowWbtc);
        borrower1.borrow(cUsdt, to6Decimals(toBorrow));

        // Avoid stack too deep error
        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (states.collateralValue, states.debtValue, states.maxDebtValue) = positionsManager
        .getUserBalanceStates(address(borrower1));

        // USDC data
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);
        uint256 collateralValueToAdd = to6Decimals(amount).mul(collateralFactor);
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += collateralValueToAdd.mul(collateralFactor);

        // DAI data
        collateralValueToAdd = amount.mul(oracle.getUnderlyingPrice(cDai));
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += (collateralValueToAdd.mul(collateralFactor));

        expectedStates.debtValue += toBorrowWbtc.mul(oracle.getUnderlyingPrice(cWbtc));
        expectedStates.debtValue += to6Decimals(toBorrow).mul(oracle.getUnderlyingPrice(usdt));

        assertEq(states.collateralValue, expectedStates.collateralValue);
        assertEq(states.debtValue, expectedStates.debtValue);
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue);
        assertEq(states.liquidationValue, expectedStates.liquidationValue);
    }

    /// This test is to check that a call to getUserLiquidityDataForAsset with USDT doesn't end
    ///   with error "Division or modulo by zero", as Aave returns 0 for USDT liquidationThreshold.
    function test_get_user_liquidity_data_for_usdt() public {
        uint256 usdtAmount = to6Decimals(10_000 ether);

        writeBalanceOf(address(borrower1), usdt, usdtAmount);
        borrower1.approve(usdt, usdtAmount);
        borrower1.supply(cUsdt, usdtAmount);

        (uint256 withdrawableUsdt, uint256 borrowableUsdt) = positionsManager
        .getUserMaxCapacitiesForAsset(address(borrower1), cUsdt);

        assertEq(withdrawableUsdt, usdtAmount, "withdrawable USDT");
        assertEq(borrowableUsdt, 0, "borrowable USDT");

        (uint256 withdrawableDai, uint256 borrowableDai) = positionsManager
        .getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        assertEq(withdrawableDai, 0, "withdrawable DAI");
        assertEq(borrowableDai, 0, "borrowable DAI");
    }

    function test_get_user_liquidity_data_with_differents_assets_and_usdt() public {
        uint256 amount = 10000 ether;
        uint256 toBorrow = 100 ether;

        writeBalanceOf(address(borrower1), usdt, to6Decimals(amount));
        borrower1.approve(usdt, to6Decimals(amount));
        borrower1.supply(cUsdt, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        borrower1.borrow(cUsdc, to6Decimals(toBorrow));
        borrower1.borrow(cUsdt, to6Decimals(toBorrow));

        // Avoid stack too deep error
        UserBalanceStates memory states;
        UserBalanceStates memory expectedStates;

        (states.collateralValue, states.debtValue, states.maxDebtValue) = positionsManager
        .getUserBalanceStates(address(borrower1));

        // USDT data
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdt);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cUsdt);

        uint256 collateralValueToAdd = to6Decimals(amount).mul(underlyingPrice);
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += collateralValueToAdd.mul(collateralFactor);

        // DAI data
        (, collateralFactor, ) = comptroller.markets(cDai);
        collateralValueToAdd = amount.mul(oracle.getUnderlyingPrice(cDai));
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += (collateralValueToAdd.mul(collateralFactor));

        // USDC data
        expectedStates.debtValue += to6Decimals(toBorrow).mul(oracle.getUnderlyingPrice(cUsdc));

        // USDT data
        expectedStates.debtValue += to6Decimals(toBorrow).mul(oracle.getUnderlyingPrice(usdt));

        testEquality(states.collateralValue, expectedStates.collateralValue, "collateralValue");
        testEquality(states.debtValue, expectedStates.debtValue, "debtValue");
        testEquality(states.maxDebtValue, expectedStates.maxDebtValue, "maxDebtValue");
        testEquality(states.liquidationValue, expectedStates.liquidationValue, "liquidationValue");
    }
}
