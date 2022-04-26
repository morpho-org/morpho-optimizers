// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

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

    function testGetHead() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 10;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        assertEq(
            address(0),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.SUPPLIERS_IN_P2P)
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.SUPPLIERS_ON_POOL)
        );
        assertEq(
            address(0),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.BORROWERS_IN_P2P)
        );
        assertEq(
            address(0),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.BORROWERS_ON_POOL)
        );

        borrower1.borrow(cDai, toBorrow);

        assertEq(
            address(borrower1),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.SUPPLIERS_IN_P2P)
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.SUPPLIERS_ON_POOL)
        );
        assertEq(
            address(borrower1),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.BORROWERS_IN_P2P)
        );
        assertEq(
            address(0),
            positionsManager.getHead(cDai, PositionsManagerStorage.PositionType.BORROWERS_ON_POOL)
        );

        borrower1.borrow(cUsdc, to6Decimals(toBorrow));

        assertEq(
            address(borrower1),
            positionsManager.getHead(cUsdc, PositionsManagerStorage.PositionType.BORROWERS_ON_POOL)
        );
    }

    function testGetNext() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 10;

        uint256 NDS = 10;
        positionsManager.setNDS(NDS);
        createSigners(NDS);
        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].approve(dai, amount - i * 1e18);
            borrowers[i].supply(cDai, amount - i * 1e18);
            borrowers[i].borrow(cUsdc, to6Decimals(toBorrow - i * 1e18));
        }

        address nextSupplyOnPool = address(borrowers[0]);
        address nextBorrowOnPool = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyOnPool = positionsManager.getNext(
                cDai,
                PositionsManagerStorage.PositionType.SUPPLIERS_ON_POOL,
                nextSupplyOnPool
            );
            nextBorrowOnPool = positionsManager.getNext(
                cUsdc,
                PositionsManagerStorage.PositionType.BORROWERS_ON_POOL,
                nextBorrowOnPool
            );

            assertEq(nextSupplyOnPool, address(borrowers[i + 1]));
            assertEq(nextBorrowOnPool, address(borrowers[i + 1]));
        }

        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].borrow(cDai, (amount / 100) - i * 1e18);
        }

        for (uint256 i; i < suppliers.length; i++) {
            suppliers[i].approve(usdc, to6Decimals(toBorrow - i * 1e18));
            suppliers[i].supply(cUsdc, to6Decimals(toBorrow - i * 1e18));
        }

        address nextSupplyInP2P = address(suppliers[0]);
        address nextBorrowInP2P = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyInP2P = positionsManager.getNext(
                cUsdc,
                PositionsManagerStorage.PositionType.SUPPLIERS_IN_P2P,
                nextSupplyInP2P
            );
            nextBorrowInP2P = positionsManager.getNext(
                cDai,
                PositionsManagerStorage.PositionType.BORROWERS_IN_P2P,
                nextBorrowInP2P
            );

            assertEq(address(suppliers[i + 1]), nextSupplyInP2P);
            assertEq(address(borrowers[i + 1]), nextBorrowInP2P);
        }
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        PositionsManager.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        assertEq(assetData.collateralFactor, collateralFactor);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.collateralValue, 0);
        assertEq(assetData.maxDebtValue, 0);
        assertEq(assetData.debtValue, 0);
    }

    function testUserLiquidityDataForAssetWithSupply() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        PositionsManager.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        uint256 collateralValue = getBalanceOnCompound(amount, ICToken(cDai).exchangeRateStored())
        .mul(underlyingPrice);
        uint256 maxDebtValue = collateralValue.mul(collateralFactor);

        assertEq(assetData.collateralFactor, collateralFactor, "collateralFactor");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.collateralValue, collateralValue, "collateralValue");
        assertEq(assetData.maxDebtValue, maxDebtValue, "maxDebtValue");
        assertEq(assetData.debtValue, 0, "debtValue");
    }

    struct Indexes {
        uint256 index1;
        uint256 index2;
    }

    function testUserLiquidityDataForAssetWithSupplyAndBorrow() public {
        Indexes memory indexes;
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 2;

        borrower1.approve(dai, amount);
        indexes.index1 = ICToken(cDai).exchangeRateCurrent();
        borrower1.supply(cDai, amount);
        uint256 borrowP2PIndex = marketsManager.borrowP2PIndex(cDai);
        borrower1.borrow(cDai, toBorrow);

        indexes.index2 = ICToken(cDai).exchangeRateCurrent();

        PositionsManager.AssetLiquidityData memory assetData = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        uint256 total;

        {
            uint256 onPool = amount.div(indexes.index1);
            uint256 matchedInP2P = toBorrow.div(marketsManager.supplyP2PIndex(cDai));
            uint256 onPoolAfter = onPool - toBorrow.div(indexes.index2);
            total =
                onPoolAfter.mul(indexes.index2) +
                matchedInP2P.mul(marketsManager.supplyP2PIndex(cDai));
        }

        uint256 collateralValue = total.mul(underlyingPrice);
        uint256 maxDebtValue = collateralValue.mul(collateralFactor);
        // Divide and multiply to take into account rouding errors.
        uint256 debtValue = toBorrow.div(borrowP2PIndex).mul(borrowP2PIndex).mul(underlyingPrice);

        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.collateralValue, collateralValue, "collateralValue");
        assertEq(assetData.maxDebtValue, maxDebtValue, "maxDebtValue");
        assertEq(assetData.debtValue, debtValue, "debtValue");
    }

    function testUserLiquidityDataForAssetWithSupplyAndBorrowWithMultipleAssets() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        PositionsManager.AssetLiquidityData memory assetDatacDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        PositionsManager.AssetLiquidityData memory assetDatacUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cUsdc, oracle);

        // Avoid stack too deep error.
        PositionsManager.AssetLiquidityData memory expectedDatcUsdc;
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);
        expectedDatcUsdc.underlyingPrice = oracle.getUnderlyingPrice(cUsdc);

        expectedDatcUsdc.debtValue = getBalanceOnCompound(toBorrow, ICToken(cUsdc).borrowIndex())
        .mul(expectedDatcUsdc.underlyingPrice);

        assertEq(
            assetDatacUsdc.underlyingPrice,
            expectedDatcUsdc.underlyingPrice,
            "underlyingPriceUsdc"
        );
        assertEq(assetDatacUsdc.collateralValue, 0, "collateralValue");
        assertEq(assetDatacUsdc.maxDebtValue, 0, "maxDebtValue");
        assertEq(assetDatacUsdc.debtValue, expectedDatcUsdc.debtValue, "debtValueUsdc");

        // Avoid stack too deep error.
        PositionsManager.AssetLiquidityData memory expectedDatacDai;

        (, expectedDatacDai.collateralFactor, ) = comptroller.markets(cDai);

        expectedDatacDai.underlyingPrice = oracle.getUnderlyingPrice(cDai);
        expectedDatacDai.collateralValue = getBalanceOnCompound(
            amount,
            ICToken(cDai).exchangeRateStored()
        ).mul(expectedDatacDai.underlyingPrice);
        expectedDatacDai.maxDebtValue = expectedDatacDai.collateralValue.mul(
            expectedDatacDai.collateralFactor
        );

        assertEq(assetDatacDai.collateralFactor, collateralFactor, "collateralFactor");
        assertEq(
            assetDatacDai.underlyingPrice,
            expectedDatacDai.underlyingPrice,
            "underlyingPriceDai"
        );

        assertEq(
            assetDatacDai.collateralValue,
            expectedDatacDai.collateralValue,
            "collateralValueDai"
        );
        assertEq(assetDatacDai.maxDebtValue, expectedDatacDai.maxDebtValue, "maxDebtValueDai");
        assertEq(assetDatacDai.debtValue, 0, "debtValueDai");
    }

    function testGetterUserWithNothing() public {
        (uint256 withdrawable, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        assertEq(withdrawable, 0);
        assertEq(borrowable, 0);
    }

    function testMaxCapicitiesWithNothingWithSupply() public {
        uint256 amount = to6Decimals(10000 ether);

        borrower1.approve(usdc, amount);
        borrower1.supply(cUsdc, amount);

        PositionsManager.AssetLiquidityData memory assetDatacUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cUsdc, oracle);

        PositionsManager.AssetLiquidityData memory assetDatacDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        uint256 expectedBorrowableUsdc = assetDatacUsdc.maxDebtValue.div(
            assetDatacUsdc.underlyingPrice
        );
        uint256 expectedBorrowableDai = assetDatacUsdc.maxDebtValue.div(
            assetDatacDai.underlyingPrice
        );

        (uint256 withdrawable, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdc
        );

        assertApproxEq(
            withdrawable,
            getBalanceOnCompound(amount, ICToken(cUsdc).exchangeRateStored()),
            1,
            "withdrawable USDC"
        );
        assertEq(borrowable, expectedBorrowableUsdc, "borrowable USDC");

        (withdrawable, borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
    }

    function testMaxCapicitiesWithNothingWithSupplyWithMultipleAssetsAndBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        PositionsManager.AssetLiquidityData memory assetDatacUsdc = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cUsdc, oracle);

        PositionsManager.AssetLiquidityData memory assetDatacDai = positionsManager
        .getUserLiquidityDataForAsset(address(borrower1), cDai, oracle);

        PositionsManager.AssetLiquidityData memory assetDatacUsdt = positionsManager
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

        uint256 expectedBorrowableUsdt = (assetDatacDai.maxDebtValue + assetDatacUsdc.maxDebtValue)
        .div(assetDatacUsdt.underlyingPrice);

        assertEq(
            withdrawableUsdc,
            getBalanceOnCompound(to6Decimals(amount), ICToken(cUsdc).exchangeRateCurrent()),
            "withdrawable USDC"
        );
        assertApproxEq(
            withdrawableDai,
            getBalanceOnCompound(amount, ICToken(cDai).exchangeRateCurrent()),
            1,
            "withdrawable DAI"
        );
        assertEq(borrowableUsdt, expectedBorrowableUsdt, "borrowable USDT before");

        uint256 toBorrow = to6Decimals(100 ether);
        borrower1.borrow(cUsdt, toBorrow);

        (, uint256 newBorrowableUsdt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdt
        );

        expectedBorrowableUsdt -= toBorrow;

        assertApproxEq(newBorrowableUsdt, expectedBorrowableUsdt, 1, "borrowable USDT after");
    }

    function testUserBalanceStatesWithSupplyAndBorrow() public {
        uint256 amount = 10_000 ether;
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
        expectedStates.collateralValue = getBalanceOnCompound(
            amount,
            ICToken(cDai).exchangeRateStored()
        ).mul(underlyingPriceDai);

        expectedStates.debtValue = getBalanceOnCompound(toBorrow, ICToken(cUsdc).borrowIndex()).mul(
            underlyingPriceUsdc
        );
        expectedStates.maxDebtValue = expectedStates.collateralValue.mul(collateralFactor);

        assertEq(states.collateralValue, expectedStates.collateralValue, "Collateral Value");
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue, "Max Debt Value");
        assertEq(states.debtValue, expectedStates.debtValue, "Debt Value");
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
        expectedStates.collateralValue += collateralValueToAdd;
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);
        expectedStates.maxDebtValue += collateralValueToAdd.mul(collateralFactor);

        // DAI data
        collateralValueToAdd = getBalanceOnCompound(amount, ICToken(cDai).exchangeRateStored()).mul(
            oracle.getUnderlyingPrice(cDai)
        );
        expectedStates.collateralValue += collateralValueToAdd;
        (, collateralFactor, ) = comptroller.markets(cDai);
        expectedStates.maxDebtValue += collateralValueToAdd.mul(collateralFactor);

        // BAT
        expectedStates.debtValue += getBalanceOnCompound(toBorrow, ICToken(cBat).borrowIndex()).mul(
            oracle.getUnderlyingPrice(cBat)
        );
        // USDT
        expectedStates.debtValue += getBalanceOnCompound(
            to6Decimals(toBorrow),
            ICToken(cBat).borrowIndex()
        ).mul(oracle.getUnderlyingPrice(cUsdt));

        (states.collateralValue, states.debtValue, states.maxDebtValue) = positionsManager
        .getUserBalanceStates(address(borrower1));

        assertEq(states.collateralValue, expectedStates.collateralValue, "Collateral Value");
        assertEq(states.debtValue, expectedStates.debtValue, "Debt Value");
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue, "Max Debt Value");
    }

    /// This test is to check that a call to getUserLiquidityDataForAsset with USDT doesn't end
    ///   with error "Division or modulo by zero", as Compound returns 0 for USDT collateralFactor.
    function testLiquidityDataForUSDT() public {
        uint256 usdtAmount = to6Decimals(10_000 ether);

        tip(usdt, address(borrower1), usdtAmount);
        borrower1.approve(usdt, usdtAmount);
        borrower1.supply(cUsdt, usdtAmount);

        (uint256 withdrawableUsdt, uint256 borrowableUsdt) = positionsManager
        .getUserMaxCapacitiesForAsset(address(borrower1), cUsdt);

        uint256 depositedUsdtAmount = getBalanceOnCompound(
            usdtAmount,
            ICToken(cUsdt).exchangeRateStored()
        );

        assertEq(withdrawableUsdt, depositedUsdtAmount, "withdrawable USDT");
        assertEq(borrowableUsdt, 0, "borrowable USDT");

        (uint256 withdrawableDai, uint256 borrowableDai) = positionsManager
        .getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        assertEq(withdrawableDai, 0, "withdrawable DAI");
        assertEq(borrowableDai, 0, "borrowable DAI");
    }

    function testLiquidityDataWithMultipleAssetsAndUSDT() public {
        Indexes memory indexes;
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(100 ether);

        tip(usdt, address(borrower1), to6Decimals(amount));
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

        (states.collateralValue, states.debtValue, states.maxDebtValue) = positionsManager
        .getUserBalanceStates(address(borrower1));

        // We must take into account that not everything is on pool as borrower1 is matched to itself.
        uint256 total;

        {
            uint256 onPool = to6Decimals(amount).div(indexes.index1);
            uint256 matchedInP2P = toBorrow.div(marketsManager.supplyP2PIndex(cUsdt));
            uint256 onPoolAfter = onPool - toBorrow.div(indexes.index2);
            total =
                onPoolAfter.mul(indexes.index2) +
                matchedInP2P.mul(marketsManager.supplyP2PIndex(cUsdt));
        }

        // USDT data
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdt);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cUsdt);

        uint256 collateralValueToAdd = total.mul(underlyingPrice);
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += collateralValueToAdd.mul(collateralFactor);

        // DAI data
        (, collateralFactor, ) = comptroller.markets(cDai);
        collateralValueToAdd = getBalanceOnCompound(amount, ICToken(cDai).exchangeRateCurrent())
        .mul(oracle.getUnderlyingPrice(cDai));
        expectedStates.collateralValue += collateralValueToAdd;
        expectedStates.maxDebtValue += collateralValueToAdd.mul(collateralFactor);

        // USDC data
        expectedStates.debtValue += getBalanceOnCompound(toBorrow, ICToken(cUsdc).borrowIndex())
        .mul(oracle.getUnderlyingPrice(cUsdc));

        // USDT data
        expectedStates.debtValue += getBalanceOnCompound(toBorrow, ICToken(cUsdt).borrowIndex())
        .mul(oracle.getUnderlyingPrice(cUsdt));

        assertEq(states.collateralValue, expectedStates.collateralValue, "Collateral Value");
        assertEq(states.debtValue, expectedStates.debtValue, "Debt Value");
        assertEq(states.maxDebtValue, expectedStates.maxDebtValue, "Max Debt Value");
    }

    function testEnteredMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(cDai, 10 ether);

        borrower1.approve(usdc, to6Decimals(10 ether));
        borrower1.supply(cUsdc, to6Decimals(10 ether));

        assertEq(positionsManager.enteredMarkets(address(borrower1), 0), cDai);
        assertEq(positionsManager.enteredMarkets(address(borrower1), 1), cUsdc);

        // Borrower1 withdraw, USDC should be the first in enteredMarkets.
        borrower1.withdraw(cDai, type(uint256).max);

        assertEq(positionsManager.enteredMarkets(address(borrower1), 0), cUsdc);
    }

    function testFailUserLeftMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(cDai, 10 ether);

        // Check that borrower1 entered Dai market.
        assertEq(positionsManager.enteredMarkets(address(borrower1), 0), cDai);

        // Borrower1 withdraw everything from the Dai market.
        borrower1.withdraw(cDai, 10 ether);

        // Test should fail because there is no element in the array.
        positionsManager.enteredMarkets(address(borrower1), 0);
    }
}
