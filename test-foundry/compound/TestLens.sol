// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/Lens.sol";
import "@contracts/compound/interfaces/IMorpho.sol";

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
    using CompoundMath for uint256;

    struct UserBalanceStates {
        uint256 collateralValue;
        uint256 debtValue;
        uint256 maxDebtValue;
        uint256 liquidationValue;
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

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

        AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

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
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
        borrower1.borrow(cDai, toBorrow);

        indexes.index2 = ICToken(cDai).exchangeRateCurrent();

        AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        (, uint256 collateralFactor, ) = comptroller.markets(cDai);
        uint256 underlyingPrice = oracle.getUnderlyingPrice(cDai);

        uint256 total;

        {
            uint256 onPool = amount.div(indexes.index1);
            uint256 matchedInP2P = toBorrow.div(morpho.p2pSupplyIndex(cDai));
            uint256 onPoolAfter = onPool - toBorrow.div(indexes.index2);
            total = onPoolAfter.mul(indexes.index2) + matchedInP2P.mul(morpho.p2pSupplyIndex(cDai));
        }

        uint256 collateralValue = total.mul(underlyingPrice);
        uint256 maxDebtValue = collateralValue.mul(collateralFactor);
        // Divide and multiply to take into account rouding errors.
        uint256 debtValue = toBorrow.div(p2pBorrowIndex).mul(p2pBorrowIndex).mul(underlyingPrice);

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

        AssetLiquidityData memory assetDatacDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        AssetLiquidityData memory assetDatacUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            oracle
        );

        // Avoid stack too deep error.
        AssetLiquidityData memory expectedDatcUsdc;
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
        AssetLiquidityData memory expectedDatacDai;

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
        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
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

        AssetLiquidityData memory assetDatacUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            oracle
        );

        AssetLiquidityData memory assetDatacDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        uint256 expectedBorrowableUsdc = assetDatacUsdc.maxDebtValue.div(
            assetDatacUsdc.underlyingPrice
        );
        uint256 expectedBorrowableDai = assetDatacUsdc.maxDebtValue.div(
            assetDatacDai.underlyingPrice
        );

        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
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

        (withdrawable, borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
    }

    function testMaxCapicitiesWithNothingWithSupplyWithMultipleAssetsAndBorrow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        AssetLiquidityData memory assetDatacUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            oracle
        );

        AssetLiquidityData memory assetDatacDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        AssetLiquidityData memory assetDatacUsdt = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdt,
            oracle
        );

        (uint256 withdrawableDai, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        (uint256 withdrawableUsdc, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdc);

        (, uint256 borrowableUsdt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdt);

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

        (, uint256 newBorrowableUsdt) = lens.getUserMaxCapacitiesForAsset(
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

        (states.collateralValue, states.debtValue, states.maxDebtValue) = lens.getUserBalanceStates(
            address(borrower1)
        );

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

        (states.collateralValue, states.debtValue, states.maxDebtValue) = lens.getUserBalanceStates(
            address(borrower1)
        );

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

        (states.collateralValue, states.debtValue, states.maxDebtValue) = lens.getUserBalanceStates(
            address(borrower1)
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

    function testGetAllMarkets() public {
        address[] memory allMarkets = morpho.getAllMarkets();

        for (uint256 i; i < pools.length; i++) {
            assertEq(allMarkets[i], pools[i]);
        }
    }

    function testGetMarketData() public {
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint32 lastUpdateBlockNumber,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        ) = lens.getMarketData(cDai);

        assertEq(p2pSupplyIndex, morpho.p2pSupplyIndex(cDai));
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(cDai));
        (uint32 expectedLastUpdateBlockNumber, , ) = morpho.lastPoolIndexes(cDai);
        assertEq(lastUpdateBlockNumber, expectedLastUpdateBlockNumber);
        (
            uint256 supplyP2PDelta,
            uint256 borrowP2PDelta,
            uint256 supplyP2PAmount,
            uint256 borrowP2PAmount
        ) = morpho.deltas(cDai);

        assertEq(supplyP2PDelta_, supplyP2PDelta);
        assertEq(borrowP2PDelta_, borrowP2PDelta);
        assertEq(supplyP2PAmount_, supplyP2PAmount);
        assertEq(borrowP2PAmount_, borrowP2PAmount);
    }

    function testGetMarketConfiguration() public {
        (
            bool isCreated,
            bool noP2P,
            bool isPaused,
            bool isPartiallyPaused,
            uint256 reserveFactor
        ) = lens.getMarketConfiguration(cDai);

        (bool isCreated_, bool isPaused_, bool isPartiallyPaused_) = morpho.marketStatuses(cDai);

        assertTrue(isCreated == isCreated_);
        assertTrue(noP2P == morpho.noP2P(cDai));

        assertTrue(isPaused == isPaused_);
        assertTrue(isPartiallyPaused == isPartiallyPaused_);
        (uint16 expectedReserveFactor, ) = morpho.marketParameters(cDai);
        assertTrue(reserveFactor == expectedReserveFactor);
    }

    function testGetUpdatedP2PIndexes() public {
        hevm.roll(block.number + (365 days * 24 * 60 * 4));
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = lens.getUpdatedP2PIndexes(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(cDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(cDai));
    }

    function testGetUpdatedP2PSupplyIndex() public {
        hevm.roll(block.number + (365 days * 24 * 60 * 4));
        uint256 newP2PSupplyIndex = lens.getUpdatedP2PSupplyIndex(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(cDai));
    }

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.roll(block.number + (365 days * 24 * 60 * 4));
        uint256 newP2PBorrowIndex = lens.getUpdatedP2PBorrowIndex(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(cDai));
    }
}
