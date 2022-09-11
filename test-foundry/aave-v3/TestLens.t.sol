// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    struct UserBalanceStates {
        uint256 collateral;
        uint256 debt;
    }

    function testCheckHealthFactor() public {
        uint256 amount = 10 ether;
        uint256 toBorrow = to6Decimals(5 ether);
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);

        (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(morpho));
        assertEq(lens.getUserHealthFactor(address(supplier1)), healthFactor, "after supply");

        supplier1.borrow(aUsdc, toBorrow);
        (, , , , , healthFactor) = pool.getUserAccountData(address(morpho));
        assertEq(lens.getUserHealthFactor(address(supplier1)), healthFactor, "after borrow");

        supplier1.withdraw(aDai, 2 ether);
        (, , , , , healthFactor) = pool.getUserAccountData(address(morpho));
        assertEq(lens.getUserHealthFactor(address(supplier1)), healthFactor, "after withdraw");

        supplier1.approve(usdc, type(uint256).max);
        supplier1.repay(aUsdc, 2 ether);
        (, , , , , healthFactor) = pool.getUserAccountData(address(morpho));
        assertEq(lens.getUserHealthFactor(address(supplier1)), healthFactor, "after repay");
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, , ) = pool
        .getConfiguration(dai)
        .getParams();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**decimals;

        assertEq(assetData.liquidationThreshold, liquidationThreshold);
        assertEq(assetData.ltv, ltv);
        assertEq(assetData.decimals, decimals);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.tokenUnit, tokenUnit);
        assertEq(assetData.collateral, 0);
        assertEq(assetData.debt, 0);
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, , ) = pool
        .getConfiguration(dai)
        .getParams();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**decimals;
        uint256 collateral = (amount * underlyingPrice) / tokenUnit;

        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertEq(assetData.collateral, collateral, "collateral");
        assertEq(assetData.debt, 0, "debt");
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, , ) = pool
        .getConfiguration(dai)
        .getParams();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**decimals;
        uint256 collateral = (amount * underlyingPrice) / tokenUnit;
        uint256 debt = (toBorrow * underlyingPrice) / tokenUnit;

        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.decimals, decimals, "decimals");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertApproxEqAbs(assetData.collateral, collateral, 2, "collateral");
        assertEq(assetData.debt, debt, "debt");
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
        uint256 decimalsUsdc;

        (expectedDataUsdc.ltv, expectedDataUsdc.liquidationThreshold, , decimalsUsdc, , ) = pool
        .getConfiguration(usdc)
        .getParams();
        expectedDataUsdc.underlyingPrice = oracle.getAssetPrice(usdc);
        expectedDataUsdc.tokenUnit = 10**decimalsUsdc;
        expectedDataUsdc.debt =
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
        assertEq(assetDataUsdc.collateral, 0, "collateralValueUsdc");
        assertEq(assetDataUsdc.debt, expectedDataUsdc.debt, "debtValueUsdc");

        Types.AssetLiquidityData memory expectedDataDai;
        uint256 decimalsDai;

        (expectedDataDai.ltv, expectedDataDai.liquidationThreshold, , decimalsDai, , ) = pool
        .getConfiguration(dai)
        .getParams();
        expectedDataDai.underlyingPrice = oracle.getAssetPrice(dai);
        expectedDataDai.tokenUnit = 10**decimalsDai;
        expectedDataDai.collateral =
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
        assertEq(assetDataDai.collateral, expectedDataDai.collateral, "collateralValueDai");
        assertEq(assetDataDai.debt, 0, "debtValueDai");
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

        uint256 expectedBorrowableUsdc = (assetDataUsdc.collateral.percentMul(assetDataUsdc.ltv) *
            assetDataUsdc.tokenUnit) / assetDataUsdc.underlyingPrice;
        uint256 expectedBorrowableDai = (assetDataUsdc.collateral.percentMul(assetDataUsdc.ltv) *
            assetDataDai.tokenUnit) / assetDataDai.underlyingPrice;

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

        uint256 expectedBorrowable = ((assetDataUsdc.collateral.percentMul(assetDataUsdc.ltv) +
            assetDataDai.collateral.percentMul(assetDataDai.ltv)) * assetDataUsdt.tokenUnit) /
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
        (, , , uint256 decimalsUsdc, , ) = pool.getConfiguration(usdc).getParams();
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**decimalsUsdc;

        // DAI data
        (uint256 ltvDai, uint256 liquidationThresholdDai, , uint256 decimalsDai, , ) = pool
        .getConfiguration(dai)
        .getParams();
        uint256 underlyingPriceDai = oracle.getAssetPrice(dai);
        uint256 tokenUnitDai = 10**decimalsDai;

        expectedStates.collateral = (amount * underlyingPriceDai) / tokenUnitDai;
        expectedStates.debt = (toBorrow * underlyingPriceUsdc) / tokenUnitUsdc;
        expectedStates.liquidationThreshold = expectedStates.collateral.percentMul(
            liquidationThresholdDai
        );
        expectedStates.maxDebt = expectedStates.collateral.percentMul(ltvDai);

        uint256 healthFactor = states.liquidationThreshold.wadDiv(states.debt);
        uint256 expectedHealthFactor = expectedStates.liquidationThreshold.wadDiv(
            expectedStates.debt
        );

        assertEq(states.collateral, expectedStates.collateral, "collateral");
        assertEq(states.debt, expectedStates.debt, "debt");
        assertEq(
            states.liquidationThreshold,
            expectedStates.liquidationThreshold,
            "liquidationThreshold"
        );
        assertEq(states.maxDebt, expectedStates.maxDebt, "maxDebt");
        assertEq(healthFactor, expectedHealthFactor, "healthFactor");
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
        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, , ) = pool
        .getConfiguration(usdc)
        .getParams();
        uint256 collateralValueToAdd = (to6Decimals(amount) * oracle.getAssetPrice(usdc)) /
            10**decimals;
        expectedStates.collateral += collateralValueToAdd;
        expectedStates.liquidationThreshold += collateralValueToAdd.percentMul(
            liquidationThreshold
        );
        expectedStates.maxDebt += collateralValueToAdd.percentMul(ltv);

        // DAI data
        (ltv, liquidationThreshold, , decimals, , ) = pool.getConfiguration(dai).getParams();
        collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**decimals;
        expectedStates.collateral += collateralValueToAdd;
        expectedStates.liquidationThreshold += collateralValueToAdd.percentMul(
            liquidationThreshold
        );
        expectedStates.maxDebt += collateralValueToAdd.percentMul(ltv);

        // WBTC data
        (, , , decimals, , ) = pool.getConfiguration(wbtc).getParams();
        expectedStates.debt += (toBorrowWbtc * oracle.getAssetPrice(wbtc)) / 10**decimals;

        // USDT data
        (, , , decimals, , ) = pool.getConfiguration(usdt).getParams();
        expectedStates.debt += (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) / 10**decimals;

        uint256 healthFactor = states.liquidationThreshold.wadDiv(states.debt);
        uint256 expectedHealthFactor = expectedStates.liquidationThreshold.wadDiv(
            expectedStates.debt
        );

        assertApproxEqAbs(states.collateral, expectedStates.collateral, 1000, "collateral");
        assertEq(states.debt, expectedStates.debt, "debt");
        assertApproxEqAbs(
            states.liquidationThreshold,
            expectedStates.liquidationThreshold,
            1000,
            "liquidationThreshold"
        );
        assertApproxEqAbs(states.maxDebt, expectedStates.maxDebt, 1000, "maxDebt");
        testEqualityLarge(healthFactor, expectedHealthFactor, "healthFactor");
    }

    function testLiquidityDataWithMultipleAssets() public {
        // TODO: fix that.
        deal(usdt, address(morpho), 1);

        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(100 ether);

        deal(usdt, address(borrower1), to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.approve(usdt, to6Decimals(amount));
        borrower1.supply(aUsdt, to6Decimals(amount));

        borrower1.borrow(aUsdt, toBorrow);
        borrower1.borrow(aUsdc, toBorrow);

        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;

        Types.LiquidityData memory expectedStates;
        Types.LiquidityData memory states = lens.getUserBalanceStates(address(borrower1));

        // USDT data
        (ltv, liquidationThreshold, , decimals, , ) = pool.getConfiguration(usdt).getParams();
        uint256 collateralValueUsdt = (to6Decimals(amount) * oracle.getAssetPrice(usdt)) /
            10**decimals;
        expectedStates.collateral += collateralValueUsdt;
        expectedStates.liquidationThreshold += collateralValueUsdt.percentMul(liquidationThreshold);
        expectedStates.maxDebt += collateralValueUsdt.percentMul(ltv);

        // DAI data
        (ltv, liquidationThreshold, , decimals, , ) = pool.getConfiguration(dai).getParams();
        uint256 collateralValueDai = (amount * oracle.getAssetPrice(dai)) / 10**decimals;
        expectedStates.collateral += collateralValueDai;
        expectedStates.liquidationThreshold += collateralValueDai.percentMul(liquidationThreshold);
        expectedStates.maxDebt += collateralValueDai.percentMul(ltv);

        // USDC data
        (, , , decimals, , ) = pool.getConfiguration(usdc).getParams();
        expectedStates.debt += (toBorrow * oracle.getAssetPrice(usdc)) / 10**decimals;

        // USDT data
        (, , , decimals, , ) = pool.getConfiguration(usdt).getParams();
        expectedStates.debt += (toBorrow * oracle.getAssetPrice(usdt)) / 10**decimals;

        uint256 healthFactor = states.liquidationThreshold.wadDiv(states.debt);
        uint256 expectedHealthFactor = expectedStates.liquidationThreshold.wadDiv(
            expectedStates.debt
        );

        testEqualityLarge(states.collateral, expectedStates.collateral, "collateral");
        assertEq(states.debt, expectedStates.debt, "debt");
        testEqualityLarge(
            states.liquidationThreshold,
            expectedStates.liquidationThreshold,
            "liquidationThreshold"
        );
        testEqualityLarge(states.maxDebt, expectedStates.maxDebt, "maxDebt");
        testEqualityLarge(healthFactor, expectedHealthFactor, "healthFactor");
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
            bool isP2PDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint256 reserveFactor
        ) = lens.getMarketConfiguration(aDai);

        (
            address underlyingToken_,
            uint16 expectedReserveFactor,
            ,
            bool isP2PDisabled_,
            bool isSupplyPaused_,
            bool isBorrowPaused_,
            bool isWithdrawPaused_,
            bool isRepayPaused_,
            bool isLiquidateCollateralPaused_,
            bool isLiquidateBorrowPaused_,

        ) = morpho.market(aDai);

        assertTrue(isCreated == (underlyingToken_ != address(0)));
        assertTrue(isP2PDisabled == isP2PDisabled_);
        assertTrue(
            isPaused ==
                (isSupplyPaused_ &&
                    isBorrowPaused_ &&
                    isWithdrawPaused_ &&
                    isRepayPaused_ &&
                    isLiquidateCollateralPaused_ &&
                    isLiquidateBorrowPaused_)
        );
        assertTrue(isPartiallyPaused == (isSupplyPaused_ && isBorrowPaused_));
        assertTrue(reserveFactor == expectedReserveFactor);
    }

    function testGetUpdatedP2PIndexes() public {
        hevm.warp(block.timestamp + 365 days);
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = lens.getUpdatedP2PIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
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
}
