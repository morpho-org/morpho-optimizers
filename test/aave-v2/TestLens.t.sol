// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/aave-v2/interfaces/lido/ILido.sol";

import "./setup/TestSetup.sol";

contract TestLens is TestSetup {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using Math for uint256;

    struct UserBalanceStates {
        uint256 collateral;
        uint256 debt;
        uint256 maxDebt;
        uint256 liquidation;
    }

    struct UserBalance {
        uint256 onPool;
        uint256 inP2P;
        uint256 totalBalance;
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aDai,
            oracle
        );

        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**decimals;

        assertEq(assetData.liquidationThreshold, liquidationThreshold);
        assertEq(assetData.ltv, ltv);
        assertEq(assetData.decimals, decimals);
        assertEq(assetData.underlyingPrice, underlyingPrice);
        assertEq(assetData.tokenUnit, tokenUnit);
        assertEq(assetData.collateralEth, 0);
        assertEq(assetData.debtEth, 0);
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**decimals;

        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertEq(assetData.collateralEth, (amount * underlyingPrice) / tokenUnit, "collateral");
        assertEq(assetData.debtEth, 0, "debt");
    }

    function testUserLiquidityDataForOtherAssetThanSupply() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            aUsdc,
            oracle
        );

        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, ) = pool
        .getConfiguration(usdc)
        .getParamsMemory();
        uint256 underlyingPrice = oracle.getAssetPrice(usdc);
        uint256 tokenUnit = 10**decimals;

        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertEq(assetData.collateralEth, 0, "collateral");
        assertEq(assetData.debtEth, 0, "debt");
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

        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPrice = oracle.getAssetPrice(dai);
        uint256 tokenUnit = 10**decimals;
        uint256 collateral = (amount * underlyingPrice) / tokenUnit;
        uint256 debt = (toBorrow * underlyingPrice) / tokenUnit;

        assertEq(assetData.liquidationThreshold, liquidationThreshold, "liquidationThreshold");
        assertEq(assetData.ltv, ltv, "ltv");
        assertEq(assetData.underlyingPrice, underlyingPrice, "underlyingPrice");
        assertEq(assetData.decimals, decimals, "decimals");
        assertEq(assetData.tokenUnit, tokenUnit, "tokenUnit");
        assertApproxEqAbs(assetData.collateralEth, collateral, 2, "collateral");
        assertEq(assetData.debtEth, debt, "debt");
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

        (expectedDataUsdc.ltv, expectedDataUsdc.liquidationThreshold, , decimalsUsdc, ) = pool
        .getConfiguration(usdc)
        .getParamsMemory();
        expectedDataUsdc.underlyingPrice = oracle.getAssetPrice(usdc);
        expectedDataUsdc.tokenUnit = 10**decimalsUsdc;
        expectedDataUsdc.debtEth =
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
        assertEq(assetDataUsdc.collateralEth, 0, "collateralUsdc");
        assertEq(assetDataUsdc.debtEth, expectedDataUsdc.debtEth, "debtUsdc");

        Types.AssetLiquidityData memory expectedDataDai;
        uint256 decimalsDai;

        (expectedDataDai.ltv, expectedDataDai.liquidationThreshold, , decimalsDai, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        expectedDataDai.underlyingPrice = oracle.getAssetPrice(dai);
        expectedDataDai.tokenUnit = 10**decimalsDai;
        expectedDataDai.collateralEth =
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
        assertEq(assetDataDai.collateralEth, expectedDataDai.collateralEth, "collateralDai");
        assertEq(assetDataDai.debtEth, 0, "debtDai");
    }

    function testUserHypotheticalBalanceStatesUnenteredMarket() public {
        uint256 amount = 10_001 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        uint256 hypotheticalBorrow = 500e6;
        Types.LiquidityData memory liquidityData = lens.getUserHypotheticalBalanceStates(
            address(borrower1),
            aUsdc,
            amount / 2,
            hypotheticalBorrow
        );

        (uint256 daiLtv, uint256 daiLiquidationThreshold, , uint256 daiDecimals, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        (, , , uint256 usdcDecimals, ) = pool.getConfiguration(usdc).getParamsMemory();

        uint256 collateral = (amount * oracle.getAssetPrice(dai)) / 10**daiDecimals;

        assertEq(
            liquidityData.maxDebtEth,
            collateral.percentMul(daiLiquidationThreshold),
            "maxDebtEth"
        );
        assertEq(liquidityData.borrowableEth, collateral.percentMul(daiLtv), "borrowableEth");
        assertEq(liquidityData.collateralEth, collateral, "collateralEth");
        assertEq(
            liquidityData.debtEth,
            (hypotheticalBorrow * oracle.getAssetPrice(usdc)).divUp(10**usdcDecimals),
            "debt"
        );
    }

    function testUserHypotheticalBalanceStatesAfterUnauthorisedBorrowWithdraw() public {
        uint256 amount = 10_001 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);

        uint256 hypotheticalWithdraw = 2 * amount;
        uint256 hypotheticalBorrow = amount;
        Types.LiquidityData memory liquidityData = lens.getUserHypotheticalBalanceStates(
            address(borrower1),
            aDai,
            hypotheticalWithdraw,
            hypotheticalBorrow
        );

        (, , , uint256 daiDecimals, ) = pool.getConfiguration(dai).getParamsMemory();

        assertEq(liquidityData.maxDebtEth, 0, "maxDebtEth");
        assertEq(liquidityData.borrowableEth, 0, "borrowableEth");
        assertEq(liquidityData.collateralEth, 0, "collateralEth");
        assertEq(
            liquidityData.debtEth,
            (hypotheticalBorrow * oracle.getAssetPrice(dai)).divUp(10**daiDecimals),
            "debtEth"
        );
    }

    function testMaxCapacitiesWithNothing() public {
        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aDai
        );

        assertEq(withdrawable, 0);
        assertEq(borrowable, 0);
    }

    function testMaxCapacitiesWithSupply() public {
        uint256 amount = to6Decimals(10000 ether);

        borrower1.approve(usdc, amount);
        borrower1.supply(aUsdc, amount);

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

        uint256 expectedBorrowableUsdc = (assetDataUsdc.collateralEth.percentMul(
            assetDataUsdc.ltv
        ) * assetDataUsdc.tokenUnit) / assetDataUsdc.underlyingPrice;
        uint256 expectedBorrowableDai = (assetDataUsdc.collateralEth.percentMul(assetDataUsdc.ltv) *
            assetDataDai.tokenUnit) / assetDataDai.underlyingPrice;

        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdc
        );

        assertEq(withdrawable, amount, "withdrawable USDC");
        assertEq(borrowable, expectedBorrowableUsdc, "borrowable USDC");

        (withdrawable, borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        assertEq(withdrawable, 0, "withdrawable DAI");
        assertEq(borrowable, expectedBorrowableDai, "borrowable DAI");
    }

    function testMaxCapacitiesWithSupplyAndBorrow() public {
        uint256 amount = 100 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);

        (uint256 withdrawableAaveBefore, uint256 borrowableAaveBefore) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), aAave);
        (uint256 withdrawableDaiBefore, uint256 borrowableDaiBefore) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        borrower1.borrow(aDai, borrowableDaiBefore / 2);

        (uint256 withdrawableAaveAfter, uint256 borrowableAaveAfter) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), aAave);
        (uint256 withdrawableDaiAfter, uint256 borrowableDaiAfter) = lens
        .getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        Types.AssetLiquidityData memory aaveAssetData;
        (aaveAssetData.ltv, aaveAssetData.liquidationThreshold, , , ) = pool
        .getConfiguration(aave)
        .getParamsMemory();

        assertEq(withdrawableAaveBefore, amount, "cannot withdraw all AAVE");
        assertEq(
            borrowableAaveBefore,
            amount.percentMul(aaveAssetData.ltv),
            "cannot borrow all AAVE"
        );
        assertEq(withdrawableDaiBefore, 0, "can withdraw DAI not supplied");
        assertApproxEqAbs(
            borrowableDaiBefore,
            amount.percentMul(aaveAssetData.ltv).wadMul(
                oracle.getAssetPrice(aave).wadDiv(oracle.getAssetPrice(dai))
            ),
            1e3,
            "cannot borrow all DAI"
        );
        assertEq(borrowableAaveAfter, borrowableAaveBefore / 2, "cannot borrow half AAVE");
        assertEq(withdrawableDaiAfter, 0, "unexpected withdrawable DAI");
        assertEq(borrowableDaiAfter, borrowableDaiBefore / 2, "cannot borrow half DAI");

        vm.expectRevert(ExitPositionsManager.UnauthorisedWithdraw.selector);
        borrower1.withdraw(aAave, withdrawableAaveAfter + 1e8);
    }

    function testUserBalanceWithoutMatching() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        UserBalance memory userSupplyBalance;

        (userSupplyBalance.inP2P, userSupplyBalance.onPool, userSupplyBalance.totalBalance) = lens
        .getCurrentSupplyBalanceInOf(aDai, address(borrower1));

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.rayMul(morpho.p2pSupplyIndex(aDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.rayMul(
            pool.getReserveNormalizedIncome(dai)
        );
        uint256 expectedTotalSupplyBalance = expectedSupplyBalanceInP2P +
            expectedSupplyBalanceOnPool;

        assertEq(userSupplyBalance.onPool, expectedSupplyBalanceOnPool, "On pool supply balance");
        assertEq(userSupplyBalance.inP2P, expectedSupplyBalanceInP2P, "P2P supply balance");
        assertEq(
            userSupplyBalance.totalBalance,
            expectedTotalSupplyBalance,
            "Total supply balance"
        );

        UserBalance memory userBorrowBalance;

        (userBorrowBalance.inP2P, userBorrowBalance.onPool, userBorrowBalance.totalBalance) = lens
        .getCurrentBorrowBalanceInOf(aUsdc, address(borrower1));

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.rayMul(
            morpho.p2pBorrowIndex(aUsdc)
        );
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.rayMul(
            pool.getReserveNormalizedVariableDebt(usdc)
        );
        uint256 expectedTotalBorrowBalance = expectedBorrowBalanceInP2P +
            expectedBorrowBalanceOnPool;

        assertEq(userBorrowBalance.onPool, expectedBorrowBalanceOnPool, "On pool borrow balance");
        assertEq(userBorrowBalance.inP2P, expectedBorrowBalanceInP2P, "P2P borrow balance");
        assertEq(
            userBorrowBalance.totalBalance,
            expectedTotalBorrowBalance,
            "Total borrow balance"
        );
    }

    function testUserBalanceWithMatching() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aUsdc, toBorrow);

        uint256 toMatch = toBorrow / 2;
        supplier1.approve(usdc, toMatch);
        supplier1.supply(aUsdc, toMatch);

        // borrower 1 supply balance (not matched)
        UserBalance memory userSupplyBalance;

        (userSupplyBalance.inP2P, userSupplyBalance.onPool, userSupplyBalance.totalBalance) = lens
        .getCurrentSupplyBalanceInOf(aDai, address(borrower1));

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            aDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.rayMul(morpho.p2pSupplyIndex(aDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.rayMul(
            pool.getReserveNormalizedIncome(dai)
        );

        assertEq(userSupplyBalance.onPool, expectedSupplyBalanceOnPool, "On pool supply balance");
        assertEq(userSupplyBalance.inP2P, expectedSupplyBalanceInP2P, "P2P supply balance");
        assertEq(
            userSupplyBalance.totalBalance,
            expectedSupplyBalanceOnPool + expectedSupplyBalanceInP2P,
            "Total supply balance"
        );

        // borrower 1 borrow balance (partially matched)
        UserBalance memory userBorrowBalance;

        (userBorrowBalance.inP2P, userBorrowBalance.onPool, userBorrowBalance.totalBalance) = lens
        .getCurrentBorrowBalanceInOf(aUsdc, address(borrower1));

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            aUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.rayMul(
            morpho.p2pBorrowIndex(aUsdc)
        );
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.rayMul(
            pool.getReserveNormalizedVariableDebt(usdc)
        );

        assertEq(userBorrowBalance.onPool, expectedBorrowBalanceOnPool, "On pool borrow balance");
        assertEq(userBorrowBalance.inP2P, expectedBorrowBalanceInP2P, "P2P borrow balance");
        assertEq(
            userBorrowBalance.totalBalance,
            expectedBorrowBalanceOnPool + expectedBorrowBalanceInP2P,
            "Total borrow balance"
        );

        // borrower 2 supply balance (pure supplier fully matched)
        UserBalance memory matchedSupplierSupplyBalance;

        (
            matchedSupplierSupplyBalance.inP2P,
            matchedSupplierSupplyBalance.onPool,
            matchedSupplierSupplyBalance.totalBalance
        ) = lens.getCurrentSupplyBalanceInOf(aUsdc, address(supplier1));

        (supplyBalanceInP2P, supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            aUsdc,
            address(supplier1)
        );

        expectedSupplyBalanceInP2P = supplyBalanceInP2P.rayMul(morpho.p2pSupplyIndex(aUsdc));
        expectedSupplyBalanceOnPool = supplyBalanceOnPool.rayMul(
            pool.getReserveNormalizedIncome(usdc)
        );

        assertEq(
            matchedSupplierSupplyBalance.onPool,
            expectedSupplyBalanceOnPool,
            "On pool matched supplier balance"
        );
        assertEq(
            matchedSupplierSupplyBalance.inP2P,
            expectedSupplyBalanceInP2P,
            "P2P matched supplier balance"
        );
        assertEq(
            matchedSupplierSupplyBalance.totalBalance,
            expectedSupplyBalanceOnPool + expectedSupplyBalanceInP2P,
            "Total matched supplier balance"
        );
    }

    function testMaxCapacitiesWithNothingWithSupplyWithMultipleAssetsAndBorrow() public {
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

        uint256 expectedBorrowableUsdt = ((assetDataUsdc.collateralEth.percentMul(
            assetDataUsdc.ltv
        ) + assetDataDai.collateralEth.percentMul(assetDataDai.ltv)) * assetDataUsdt.tokenUnit) /
            assetDataUsdt.underlyingPrice;

        assertEq(withdrawableUsdc, to6Decimals(amount), "unexpected new withdrawable usdc");
        assertEq(withdrawableDai, amount, "unexpected new withdrawable dai");
        assertEq(borrowableUsdt, expectedBorrowableUsdt, "unexpected borrowable usdt");

        uint256 toBorrow = to6Decimals(100 ether);
        borrower1.borrow(aUsdt, toBorrow);

        (, uint256 newBorrowableUsdt) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            aUsdt
        );

        expectedBorrowableUsdt -= toBorrow;

        assertEq(newBorrowableUsdt, expectedBorrowableUsdt, "unexpected new borrowable usdt");
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
        (, , , uint256 decimalsUsdc, ) = pool.getConfiguration(usdc).getParamsMemory();
        uint256 underlyingPriceUsdc = oracle.getAssetPrice(usdc);
        uint256 tokenUnitUsdc = 10**decimalsUsdc;

        // DAI data
        (uint256 ltvDai, uint256 liquidationThresholdDai, , uint256 decimalsDai, ) = pool
        .getConfiguration(dai)
        .getParamsMemory();
        uint256 underlyingPriceDai = oracle.getAssetPrice(dai);
        uint256 tokenUnitDai = 10**decimalsDai;

        expectedStates.collateralEth = (amount * underlyingPriceDai) / tokenUnitDai;
        expectedStates.debtEth = (toBorrow * underlyingPriceUsdc) / tokenUnitUsdc;
        expectedStates.maxDebtEth = expectedStates.collateralEth.percentMul(
            liquidationThresholdDai
        );
        expectedStates.borrowableEth = expectedStates.collateralEth.percentMul(ltvDai);

        uint256 healthFactor = states.maxDebtEth.wadDiv(states.debtEth);
        uint256 expectedHealthFactor = expectedStates.maxDebtEth.wadDiv(expectedStates.debtEth);

        assertEq(states.collateralEth, expectedStates.collateralEth, "collateral");
        assertEq(states.debtEth, expectedStates.debtEth, "debt");
        assertEq(states.maxDebtEth, expectedStates.maxDebtEth, "liquidationThreshold");
        assertEq(states.borrowableEth, expectedStates.borrowableEth, "maxDebt");
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
        (uint256 ltv, uint256 liquidationThreshold, , uint256 decimals, ) = pool
        .getConfiguration(usdc)
        .getParamsMemory();
        uint256 collateralValueToAdd = (to6Decimals(amount) * oracle.getAssetPrice(usdc)) /
            10**decimals;
        expectedStates.collateralEth += collateralValueToAdd;
        expectedStates.maxDebtEth += collateralValueToAdd.percentMul(liquidationThreshold);
        expectedStates.borrowableEth += collateralValueToAdd.percentMul(ltv);

        // DAI data
        (ltv, liquidationThreshold, , decimals, ) = pool.getConfiguration(dai).getParamsMemory();
        collateralValueToAdd = (amount * oracle.getAssetPrice(dai)) / 10**decimals;
        expectedStates.collateralEth += collateralValueToAdd;
        expectedStates.maxDebtEth += collateralValueToAdd.percentMul(liquidationThreshold);
        expectedStates.borrowableEth += collateralValueToAdd.percentMul(ltv);

        // WBTC data
        (, , , decimals, ) = pool.getConfiguration(wbtc).getParamsMemory();
        expectedStates.debtEth += (toBorrowWbtc * oracle.getAssetPrice(wbtc)) / 10**decimals;

        // USDT data
        (, , , decimals, ) = pool.getConfiguration(usdt).getParamsMemory();
        expectedStates.debtEth +=
            (to6Decimals(toBorrow) * oracle.getAssetPrice(usdt)) /
            10**decimals;

        uint256 healthFactor = states.maxDebtEth.wadDiv(states.debtEth);
        uint256 expectedHealthFactor = expectedStates.maxDebtEth.wadDiv(expectedStates.debtEth);

        assertApproxEqAbs(states.collateralEth, expectedStates.collateralEth, 2, "collateral");
        assertApproxEqAbs(states.debtEth, expectedStates.debtEth, 1, "debt");
        assertEq(states.maxDebtEth, expectedStates.maxDebtEth, "liquidationThreshold");
        assertEq(states.borrowableEth, expectedStates.borrowableEth, "maxDebt");
        assertApproxEqAbs(healthFactor, expectedHealthFactor, 1e4, "healthFactor");
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

        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;

        Types.LiquidityData memory expectedStates;
        Types.LiquidityData memory states = lens.getUserBalanceStates(address(borrower1));

        // USDT data
        (ltv, liquidationThreshold, , decimals, ) = pool.getConfiguration(usdt).getParamsMemory();
        uint256 collateralValueUsdt = (to6Decimals(amount) * oracle.getAssetPrice(usdt)) /
            10**decimals;
        expectedStates.collateralEth += collateralValueUsdt;
        expectedStates.maxDebtEth += collateralValueUsdt.percentMul(liquidationThreshold);
        expectedStates.borrowableEth += collateralValueUsdt.percentMul(ltv);

        // DAI data
        (ltv, liquidationThreshold, , decimals, ) = pool.getConfiguration(dai).getParamsMemory();
        uint256 collateralValueDai = (amount * oracle.getAssetPrice(dai)) / 10**decimals;
        expectedStates.collateralEth += collateralValueDai;
        expectedStates.maxDebtEth += collateralValueDai.percentMul(liquidationThreshold);
        expectedStates.borrowableEth += collateralValueDai.percentMul(ltv);

        // USDC data
        (, , , decimals, ) = pool.getConfiguration(usdc).getParamsMemory();
        expectedStates.debtEth += (toBorrow * oracle.getAssetPrice(usdc)) / 10**decimals;

        // USDT data
        (, , , decimals, ) = pool.getConfiguration(usdt).getParamsMemory();
        expectedStates.debtEth += (toBorrow * oracle.getAssetPrice(usdt)) / 10**decimals;

        uint256 healthFactor = states.maxDebtEth.wadDiv(states.debtEth);
        uint256 expectedHealthFactor = expectedStates.maxDebtEth.wadDiv(expectedStates.debtEth);

        assertApproxEqAbs(states.collateralEth, expectedStates.collateralEth, 1e3, "collateral");
        assertEq(states.debtEth, expectedStates.debtEth, "debt");
        assertEq(states.maxDebtEth, expectedStates.maxDebtEth, "liquidationThreshold");
        assertEq(states.borrowableEth, expectedStates.borrowableEth, "maxDebt");
        assertEq(healthFactor, expectedHealthFactor, "healthFactor");
    }

    function testGetMainMarketData() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, amount);
        borrower1.supply(aDai, amount);
        borrower1.borrow(aDai, amount / 2);

        (
            ,
            ,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount,
            uint256 poolSupplyAmount,
            uint256 poolBorrowAmount
        ) = lens.getMainMarketData(aDai);

        assertApproxEqAbs(p2pSupplyAmount, p2pBorrowAmount, 1e9);
        assertApproxEqAbs(p2pSupplyAmount, amount / 2, 1e9);
        assertApproxEqAbs(poolSupplyAmount, amount / 2, 1e9);
        assertApproxEqAbs(poolBorrowAmount, 0, 1e4);
    }

    function testGetMarketConfiguration() public {
        (
            address underlying,
            bool isCreated,
            bool isP2PDisabled,
            bool isPaused,
            bool isPartiallyPaused,
            uint16 reserveFactor,
            uint16 p2pIndexCursor,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 decimals
        ) = lens.getMarketConfiguration(aDai);
        assertEq(underlying, dai);

        (
            ,
            ,
            ,
            bool isCreated_,
            bool isPaused_,
            bool isPartiallyPaused_,
            bool isP2PDisabled_
        ) = morpho.market(aDai);

        assertEq(isCreated, isCreated_);
        assertEq(isP2PDisabled, isP2PDisabled_);

        assertEq(isPaused, isPaused_);
        assertEq(isPartiallyPaused, isPartiallyPaused_);
        (, uint16 expectedReserveFactor, uint16 expectedP2PIndexCursor, , , , ) = morpho.market(
            aDai
        );
        assertEq(reserveFactor, expectedReserveFactor);
        assertEq(p2pIndexCursor, expectedP2PIndexCursor);

        (
            uint256 expectedLtv,
            uint256 expectedLiquidationThreshold,
            uint256 expectedLiquidationBonus,
            uint256 expectedDecimals,

        ) = pool.getConfiguration(dai).getParamsMemory();

        assertEq(ltv, expectedLtv);
        assertEq(liquidationThreshold, expectedLiquidationThreshold);
        assertEq(liquidationBonus, expectedLiquidationBonus);
        assertEq(decimals, expectedDecimals);
    }

    function testGetOutdatedIndexes() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 31 days / 12);
        Types.Indexes memory indexes = lens.getIndexes(aDai);

        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(aDai),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(aDai),
            "p2p borrow indexes different"
        );

        assertEq(
            indexes.poolSupplyIndex,
            pool.getReserveNormalizedIncome(dai),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            pool.getReserveNormalizedVariableDebt(dai),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedIndexes() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(wbtc, to8Decimals(amount));
        borrower1.supply(aWbtc, to8Decimals(amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 31 days / 12);
        Types.Indexes memory indexes = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(aDai),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(aDai),
            "p2p borrow indexes different"
        );

        assertEq(
            indexes.poolSupplyIndex,
            pool.getReserveNormalizedIncome(dai),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            pool.getReserveNormalizedVariableDebt(dai),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedP2PIndexesWithSupplyDelta() public {
        _createSupplyDelta();
        hevm.warp(block.timestamp + 365 days);
        Types.Indexes memory indexes = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertApproxEqAbs(indexes.p2pBorrowIndex, morpho.p2pBorrowIndex(aDai), 1);
        assertApproxEqAbs(indexes.p2pSupplyIndex, morpho.p2pSupplyIndex(aDai), 1);
    }

    function testGetUpdatedP2PIndexesWithBorrowDelta() public {
        _createBorrowDelta();
        hevm.warp(block.timestamp + 365 days);
        Types.Indexes memory indexes = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertApproxEqAbs(indexes.p2pBorrowIndex, morpho.p2pBorrowIndex(aDai), 1);
        assertApproxEqAbs(indexes.p2pSupplyIndex, morpho.p2pSupplyIndex(aDai), 1);
    }

    function testGetUpdatedP2PSupplyIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PSupplyIndex = lens.getCurrentP2PSupplyIndex(aDai);

        morpho.updateIndexes(aDai);
        assertApproxEqAbs(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai), 1);
    }

    function testGetUpdatedP2PSupplyIndexWithDelta() public {
        _createSupplyDelta();
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PSupplyIndex = lens.getCurrentP2PSupplyIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(aDai));
    }

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getCurrentP2PBorrowIndex(aDai);

        morpho.updateIndexes(aDai);
        assertApproxEqAbs(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai), 1);
    }

    function testGetUpdatedP2PBorrowIndexWithDelta() public {
        _createBorrowDelta();
        hevm.warp(block.timestamp + 365 days);
        uint256 newP2PBorrowIndex = lens.getCurrentP2PBorrowIndex(aDai);

        morpho.updateIndexes(aDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(aDai));
    }

    function testGetUpdatedIndexesOnStEth() public {
        createMarket(aStEth);

        deal(address(supplier1), 1_000 ether);
        uint256 totalEthBalance = address(supplier1).balance;
        uint256 totalBalance = totalEthBalance / 2;
        vm.prank(address(supplier1));
        ILido(stEth).submit{value: totalBalance}(address(0));

        // Handle roundings.
        vm.prank(address(supplier1));
        ERC20(stEth).transfer(address(morpho), 100);

        uint256 amount = ERC20(stEth).balanceOf(address(supplier1));

        supplier1.approve(stEth, type(uint256).max);
        supplier1.supply(aStEth, amount);

        vm.roll(block.number + 31 days / 12);
        vm.warp(block.timestamp + 1);
        Types.Indexes memory indexes = lens.getIndexes(aStEth);

        morpho.updateIndexes(aStEth);
        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(aStEth),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(aStEth),
            "p2p borrow indexes different"
        );

        uint256 rebaseIndex = ILido(stEth).getPooledEthByShares(WadRayMath.RAY);
        uint256 baseRebaseIndex = morpho.ST_ETH_BASE_REBASE_INDEX();

        assertEq(
            indexes.poolSupplyIndex,
            pool.getReserveNormalizedIncome(stEth).rayMul(rebaseIndex).rayDiv(baseRebaseIndex),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            pool.getReserveNormalizedVariableDebt(stEth).rayMul(rebaseIndex).rayDiv(
                baseRebaseIndex
            ),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedIndexesWithInvertedSpread() public {
        supplier1.approve(dai, 1 ether);
        supplier1.supply(aDai, 1 ether);
        borrower1.approve(aave, 1 ether);
        borrower1.supply(aAave, 1 ether);
        borrower1.borrow(aDai, 1 ether);

        _invertPoolSpread(dai);

        hevm.roll(block.number + 31 days / 12);
        Types.Indexes memory indexes = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(aDai),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(aDai),
            "p2p borrow indexes different"
        );

        assertEq(
            indexes.poolSupplyIndex,
            pool.getReserveNormalizedIncome(dai),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            pool.getReserveNormalizedVariableDebt(dai),
            "pool borrow indexes different"
        );
    }

    function testGetUpdatedIndexesWithInvertedSpreadAndSupplyDelta() public {
        _createSupplyDelta();
        _invertPoolSpreadWithStorageManipulation(dai);

        hevm.roll(block.number + 31 days / 12);
        Types.Indexes memory indexes = lens.getIndexes(aDai);

        morpho.updateIndexes(aDai);
        assertEq(
            indexes.p2pSupplyIndex,
            morpho.p2pSupplyIndex(aDai),
            "p2p supply indexes different"
        );
        assertEq(
            indexes.p2pBorrowIndex,
            morpho.p2pBorrowIndex(aDai),
            "p2p borrow indexes different"
        );

        assertEq(
            indexes.poolSupplyIndex,
            pool.getReserveNormalizedIncome(dai),
            "pool supply indexes different"
        );
        assertEq(
            indexes.poolBorrowIndex,
            pool.getReserveNormalizedVariableDebt(dai),
            "pool borrow indexes different"
        );
    }

    function _createSupplyDelta() public {
        uint256 amount = 1 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, amount / 2);
        borrower1.borrow(aDai, amount / 4);

        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();

        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        borrower1.repay(aDai, type(uint256).max);

        setDefaultMaxGasForMatchingHelper(supply, borrow, withdraw, repay);
    }

    function _createBorrowDelta() public {
        uint256 amount = 1 ether;
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);

        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, amount / 2);
        borrower1.borrow(aDai, amount / 4);

        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();

        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(aDai, type(uint256).max);

        setDefaultMaxGasForMatchingHelper(supply, borrow, withdraw, repay);
    }

    function testGetAllMarkets() public {
        address[] memory lensMarkets = lens.getAllMarkets();
        address[] memory morphoMarkets = morpho.getMarketsCreated();

        for (uint256 i; i < lensMarkets.length; i++) {
            assertEq(morphoMarkets[i], lensMarkets[i]);
        }
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
        bytes32 userMarkets = morpho.userMarkets(address(supplier1));

        uint256 j;
        for (uint256 i; i < pools.length; ) {
            address market = pools[i];

            for (j = 0; j < enteredMarkets.length; ) {
                if (enteredMarkets[j] == market) break;

                unchecked {
                    ++j;
                }
            }

            bytes32 marketBitmask = morpho.borrowMask(market);
            if (userMarkets & (marketBitmask | (marketBitmask << 1)) != 0)
                assertLt(j, enteredMarkets.length, "market entered not in enteredMarkets");
            else assertEq(j, enteredMarkets.length, "market not entered in enteredMarkets");

            unchecked {
                ++i;
            }
        }
    }

    function testHealthFactorBelow1() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setDirectPrice(usdc, 0.5e18);
        oracle.setDirectPrice(dai, 1e18);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

        assertLt(healthFactor, 1e18);
    }

    function testHealthFactorAbove1() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setDirectPrice(usdc, 1e18);
        oracle.setDirectPrice(dai, 1e18);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

        (, uint256 liquidationThreshold, , , ) = pool.getConfiguration(usdc).getParamsMemory();

        assertEq(healthFactor, uint256(2 ether).percentMul(liquidationThreshold));
    }

    function testHealthFactorShouldBeInfinityForPureSuppliers() public {
        uint256 amount = to6Decimals(10_000 ether);

        supplier1.approve(usdc, amount);
        supplier1.supply(aUsdc, amount);

        uint256 healthFactor = lens.getUserHealthFactor(address(supplier1));

        assertEq(healthFactor, type(uint256).max);
    }

    function testHealthFactorAbove1WhenHalfMatched() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setDirectPrice(usdc, 1e18);
        oracle.setDirectPrice(dai, 1e18);

        supplier1.approve(dai, amount / 2);
        supplier1.supply(aDai, amount / 2);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

        (, uint256 liquidationThreshold, , , ) = pool.getConfiguration(usdc).getParamsMemory();

        assertEq(healthFactor, uint256(2 ether).percentMul(liquidationThreshold));
    }

    function testHealthFactorEqual1() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setDirectPrice(usdc, 1e18);
        oracle.setDirectPrice(dai, 1e18);

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        uint256 borrower1HealthFactor = lens.getUserHealthFactor(address(borrower1));

        oracle.setDirectPrice(usdc, 2e18); // let borrower2 borrow as much as they want

        borrower2.approve(usdc, to6Decimals(2 * amount));
        borrower2.supply(aUsdc, to6Decimals(2 * amount));
        borrower2.borrow(aDai, amount.wadMul(borrower1HealthFactor));

        oracle.setDirectPrice(usdc, 1e18);

        uint256 borrower2HealthFactor = lens.getUserHealthFactor(address(borrower2));

        assertEq(borrower2HealthFactor, 1e18);
    }

    function testHealthFactorEqual1WhenBorrowingMaxCapacity() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        hevm.roll(block.number + 1000);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), aDai);

        borrower1.borrow(aDai, borrowable);

        uint256 healthFactor = lens.getUserHealthFactor(address(borrower1));

        (uint256 ltv, uint256 liquidationThreshold, , , ) = pool
        .getConfiguration(usdc)
        .getParamsMemory();

        assertEq(healthFactor, uint256(1 ether).percentMul(liquidationThreshold).percentDiv(ltv));
    }

    function testLiquidationShouldBeNullWhenPriceTooLow() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(aDai, 2 * amount);
        borrower1.borrow(aUsdc, to6Decimals(amount));

        createAndSetCustomPriceOracle().setDirectPrice(dai, 1);

        assertApproxEqAbs(
            lens.computeLiquidationRepayAmount(address(borrower1), aUsdc, aDai),
            0,
            1e3
        );
    }

    function testLiquidationShouldBeNullWhenNotLiquidatable() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        assertEq(lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc), 0);
    }

    function testLiquidationShouldNotBeAboveCloseFactor() public {
        uint256 amount = 10_000 ether;

        createAndSetCustomPriceOracle().setDirectPrice(usdc, (oracle.getAssetPrice(dai) * 2));

        borrower1.approve(usdc, to6Decimals(amount));
        borrower1.supply(aUsdc, to6Decimals(amount));
        borrower1.borrow(aDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(
            usdc,
            ((oracle.getAssetPrice(dai) * 79) / 100)
        );

        assertApproxEqAbs(
            lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc),
            amount.percentMul(DEFAULT_LIQUIDATION_CLOSE_FACTOR),
            1
        );
    }

    function testLiquidationShouldBeHalfWhenPriceIsHalf() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(usdc, (oracle.getAssetPrice(dai) / 2));

        assertApproxEqAbs(
            lens.computeLiquidationRepayAmount(address(borrower1), aDai, aUsdc),
            amount / 2,
            1
        );
    }

    function testLiquidation(uint256 _amount, uint80 _collateralPrice) internal {
        uint256 amount = _amount + 1e14;
        uint256 collateralPrice = uint256(_collateralPrice) + 1;

        // this is necessary to avoid Morpho's health factor lower than liquidation threshold
        supplier2.approve(usdc, 100e6);
        supplier2.supply(aUsdc, 100e6);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier1));

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(aDai, 2 * amount);
        borrower1.borrow(aUsdc, to6Decimals(amount));

        hevm.roll(block.number + 1);
        createAndSetCustomPriceOracle().setDirectPrice(dai, collateralPrice);

        Types.LiquidityData memory states = lens.getUserBalanceStates(address(borrower1));

        uint256 toRepay = lens.computeLiquidationRepayAmount(address(borrower1), aUsdc, aDai);

        if (states.debtEth <= states.maxDebtEth) {
            assertEq(toRepay, 0, "Should return 0 when the position is solvent");
            return;
        }

        (, , uint256 liquidationBonus, , ) = pool.getConfiguration(dai).getParamsMemory();

        if (toRepay != 0) {
            supplier1.approve(usdc, type(uint256).max);

            do {
                supplier1.liquidate(aUsdc, aDai, address(borrower1), toRepay);
                assertLt(
                    balanceBefore,
                    balanceBefore = ERC20(dai).balanceOf(address(supplier1)),
                    "balance did not increase"
                );

                toRepay = lens.computeLiquidationRepayAmount(address(borrower1), aUsdc, aDai);
            } while (lens.isLiquidatable(address(borrower1)) && toRepay > 0);

            // either the liquidatee's position (borrow value divided by supply value) was under the [1 / liquidationBonus] threshold and returned to a solvent position
            if (states.collateralEth.percentDiv(liquidationBonus) > states.debtEth) {
                assertFalse(lens.isLiquidatable(address(borrower1)), "borrower1 liquidatable");
            } else {
                // or the liquidator has drained all the collateral
                states = lens.getUserBalanceStates(address(borrower1));
                assertGt(
                    states.debtEth,
                    states.collateralEth.percentDiv(liquidationBonus),
                    "debt value under collateral value"
                );
                assertEq(toRepay, 0, "to repay not zero");
            }
        } else {
            // liquidator cannot repay anything iff 1 wei of borrow is greater than the repayable collateral + the liquidation bonus
            assertGt(
                states.debtEth,
                states.collateralEth.percentDiv(liquidationBonus),
                "debt value under collateral value"
            );
        }
    }

    function testFuzzLiquidation(uint64 _amount, uint80 _collateralPrice) public {
        testLiquidation(uint256(_amount), _collateralPrice);
    }

    function testFuzzLiquidationUnderIncentiveThreshold(uint64 _amount) public {
        testLiquidation(uint256(_amount), 0.501 ether);
    }

    function testFuzzLiquidationAboveIncentiveThreshold(uint64 _amount) public {
        testLiquidation(uint256(_amount), 0.55 ether);
    }

    function testIsLiquidatableDeprecatedMarket() public {
        uint256 amount = 1_000 ether;

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(aDai, 2 * amount);
        borrower1.borrow(aUsdc, to6Decimals(amount));

        assertFalse(lens.isLiquidatable(address(borrower1), aUsdc));

        morpho.setIsBorrowPaused(aUsdc, true);
        morpho.setIsDeprecated(aUsdc, true);

        assertTrue(lens.isLiquidatable(address(borrower1), aUsdc));
    }

    struct Amounts {
        uint256 totalP2PSupply;
        uint256 totalPoolSupply;
        uint256 totalSupply;
        uint256 totalP2PBorrow;
        uint256 totalPoolBorrow;
        uint256 totalBorrow;
        uint256 daiP2PSupply;
        uint256 daiPoolSupply;
        uint256 daiP2PBorrow;
        uint256 daiPoolBorrow;
        uint256 ethP2PSupply;
        uint256 ethPoolSupply;
        uint256 ethP2PBorrow;
        uint256 ethPoolBorrow;
    }

    struct SupplyBorrowIndexes {
        uint256 ethPoolSupplyIndexBefore;
        uint256 daiP2PSupplyIndexBefore;
        uint256 daiP2PBorrowIndexBefore;
        uint256 ethPoolSupplyIndexAfter;
        uint256 daiPoolSupplyIndexAfter;
        uint256 daiP2PSupplyIndexAfter;
        uint256 daiP2PBorrowIndexAfter;
    }

    function testTotalSupplyBorrowWithHalfSupplyDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        SupplyBorrowIndexes memory indexes;
        indexes.ethPoolSupplyIndexBefore = pool.getReserveNormalizedIncome(aave);
        indexes.daiP2PBorrowIndexBefore = morpho.p2pBorrowIndex(aDai);

        hevm.roll(block.number + 1);

        borrower1.approve(dai, amount / 2);
        borrower1.repay(aDai, amount / 2);

        {
            SimplePriceOracle oracle = createAndSetCustomPriceOracle();
            oracle.setDirectPrice(aave, 2 ether);
            oracle.setDirectPrice(dai, 1 ether);
        }

        Amounts memory amounts;

        (amounts.totalP2PSupply, amounts.totalPoolSupply, amounts.totalSupply) = lens
        .getTotalSupply();
        (amounts.totalP2PBorrow, amounts.totalPoolBorrow, amounts.totalBorrow) = lens
        .getTotalBorrow();

        (amounts.daiP2PSupply, amounts.daiPoolSupply) = lens.getTotalMarketSupply(aDai);
        (amounts.daiP2PBorrow, amounts.daiPoolBorrow) = lens.getTotalMarketBorrow(aDai);
        (amounts.ethP2PSupply, amounts.ethPoolSupply) = lens.getTotalMarketSupply(aAave);
        (amounts.ethP2PBorrow, amounts.ethPoolBorrow) = lens.getTotalMarketBorrow(aAave);

        indexes.ethPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(aave);
        indexes.daiPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(dai);
        indexes.daiP2PBorrowIndexAfter = morpho.p2pBorrowIndex(aDai);

        uint256 expectedDaiUSDOnPool = (amount / 2).rayDiv(indexes.daiPoolSupplyIndexAfter).rayMul(
            indexes.daiPoolSupplyIndexAfter
        ); // which is also the supply delta
        uint256 expectedDaiUSDInP2P = amount.rayDiv(indexes.daiP2PBorrowIndexBefore).rayMul(
            indexes.daiP2PBorrowIndexAfter
        ) - expectedDaiUSDOnPool;
        uint256 expectedEthUSDOnPool = 2 *
            amount.rayDiv(indexes.ethPoolSupplyIndexBefore).rayMul(indexes.ethPoolSupplyIndexAfter);

        assertEq(
            amounts.totalSupply,
            expectedEthUSDOnPool + expectedDaiUSDInP2P + expectedDaiUSDOnPool,
            "unexpected total supply"
        );
        assertApproxEqAbs(amounts.totalBorrow, expectedDaiUSDInP2P, 1e8, "unexpected total borrow");

        assertEq(amounts.totalP2PSupply, expectedDaiUSDInP2P, "unexpected total p2p supply");
        assertEq(
            amounts.totalPoolSupply,
            expectedDaiUSDOnPool + expectedEthUSDOnPool,
            "unexpected total pool supply"
        );
        assertApproxEqAbs(
            amounts.totalP2PBorrow,
            expectedDaiUSDInP2P,
            1e8,
            "unexpected total p2p borrow"
        );
        assertEq(amounts.totalPoolBorrow, 0, "unexpected total pool borrow");

        assertEq(amounts.daiP2PSupply, expectedDaiUSDInP2P, "unexpected dai p2p supply");
        assertApproxEqAbs(
            amounts.daiP2PBorrow,
            expectedDaiUSDInP2P,
            1e8,
            "unexpected dai p2p borrow"
        );
        assertEq(amounts.daiPoolSupply, expectedDaiUSDOnPool, "unexpected dai pool supply");
        assertEq(amounts.daiPoolBorrow, 0, "unexpected dai pool borrow");

        assertEq(amounts.ethP2PSupply, 0, "unexpected eth p2p supply");
        assertEq(amounts.ethP2PBorrow, 0, "unexpected eth p2p borrow");
        assertEq(amounts.ethPoolSupply, expectedEthUSDOnPool / 2, "unexpected eth pool supply");
        assertEq(amounts.ethPoolBorrow, 0, "unexpected eth pool borrow");
    }

    function testTotalSupplyBorrowWithHalfBorrowDelta() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(aave, amount);
        borrower1.supply(aAave, amount);
        borrower1.borrow(aDai, amount);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 0);

        SupplyBorrowIndexes memory indexes;
        indexes.ethPoolSupplyIndexBefore = pool.getReserveNormalizedIncome(aave);
        indexes.daiP2PSupplyIndexBefore = morpho.p2pSupplyIndex(aDai);

        hevm.roll(block.number + 1);

        supplier1.withdraw(aDai, amount / 2);

        {
            SimplePriceOracle oracle = createAndSetCustomPriceOracle();
            oracle.setDirectPrice(aave, 2 ether);
            oracle.setDirectPrice(dai, 1 ether);
        }

        Amounts memory amounts;

        (amounts.totalP2PSupply, amounts.totalPoolSupply, amounts.totalSupply) = lens
        .getTotalSupply();
        (amounts.totalP2PBorrow, amounts.totalPoolBorrow, amounts.totalBorrow) = lens
        .getTotalBorrow();

        (amounts.daiP2PSupply, amounts.daiPoolSupply) = lens.getTotalMarketSupply(aDai);
        (amounts.daiP2PBorrow, amounts.daiPoolBorrow) = lens.getTotalMarketBorrow(aDai);
        (amounts.ethP2PSupply, amounts.ethPoolSupply) = lens.getTotalMarketSupply(aAave);
        (amounts.ethP2PBorrow, amounts.ethPoolBorrow) = lens.getTotalMarketBorrow(aAave);

        indexes.ethPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(aave);
        indexes.daiPoolSupplyIndexAfter = pool.getReserveNormalizedIncome(dai);
        indexes.daiP2PSupplyIndexAfter = morpho.p2pSupplyIndex(aDai);

        uint256 expectedDaiUSDOnPool = amount / 2; // which is also the borrow delta
        uint256 expectedDaiUSDInP2P = amount.rayDiv(indexes.daiP2PSupplyIndexBefore).rayMul(
            indexes.daiP2PSupplyIndexAfter
        ) - expectedDaiUSDOnPool;
        uint256 expectedEthUSDOnPool = 2 *
            amount.rayDiv(indexes.ethPoolSupplyIndexBefore).rayMul(indexes.ethPoolSupplyIndexAfter);

        assertApproxEqAbs(
            amounts.totalSupply,
            expectedEthUSDOnPool + expectedDaiUSDInP2P,
            1e9,
            "unexpected total supply"
        );
        assertApproxEqAbs(
            amounts.totalBorrow,
            expectedDaiUSDInP2P + expectedDaiUSDOnPool,
            1,
            "unexpected total borrow"
        );

        assertApproxEqAbs(
            amounts.totalP2PSupply,
            expectedDaiUSDInP2P,
            1e9,
            "unexpected total p2p supply"
        );
        assertApproxEqAbs(
            amounts.totalPoolSupply,
            expectedEthUSDOnPool,
            1,
            "unexpected total pool supply"
        );
        assertApproxEqAbs(
            amounts.totalP2PBorrow,
            expectedDaiUSDInP2P,
            1,
            "unexpected total p2p borrow"
        );
        assertEq(amounts.totalPoolBorrow, expectedDaiUSDOnPool, "unexpected total pool borrow");

        assertApproxEqAbs(
            amounts.daiP2PSupply,
            expectedDaiUSDInP2P,
            1e9,
            "unexpected dai p2p supply"
        );
        assertApproxEqAbs(
            amounts.daiP2PBorrow,
            expectedDaiUSDInP2P,
            1,
            "unexpected dai p2p borrow"
        );
        assertEq(amounts.daiPoolSupply, 0, "unexpected dai pool supply");
        assertEq(amounts.daiPoolBorrow, expectedDaiUSDOnPool, "unexpected dai pool borrow");

        assertEq(amounts.ethP2PSupply, 0, "unexpected eth p2p supply");
        assertEq(amounts.ethP2PBorrow, 0, "unexpected eth p2p borrow");
        assertEq(amounts.ethPoolSupply, expectedEthUSDOnPool / 2, "unexpected eth pool supply");
        assertEq(amounts.ethPoolBorrow, 0, "unexpected eth pool borrow");
    }

    function testGetMarketPauseStatusesDeprecatedMarket() public {
        morpho.setIsBorrowPaused(aDai, true);
        morpho.setIsDeprecated(aDai, true);
        assertTrue(lens.getMarketPauseStatus(aDai).isDeprecated);
    }

    function testGetMarketPauseStatusesPauseSupply() public {
        morpho.setIsSupplyPaused(aDai, true);
        assertTrue(lens.getMarketPauseStatus(aDai).isSupplyPaused);
    }

    function testGetMarketPauseStatusesPauseBorrow() public {
        morpho.setIsBorrowPaused(aDai, true);
        assertTrue(lens.getMarketPauseStatus(aDai).isBorrowPaused);
    }

    function testGetMarketPauseStatusesPauseWithdraw() public {
        morpho.setIsWithdrawPaused(aDai, true);
        assertTrue(lens.getMarketPauseStatus(aDai).isWithdrawPaused);
    }

    function testGetMarketPauseStatusesPauseRepay() public {
        morpho.setIsRepayPaused(aDai, true);
        assertTrue(lens.getMarketPauseStatus(aDai).isRepayPaused);
    }

    function testGetMarketPauseStatusesPauseLiquidateOnCollateral() public {
        morpho.setIsLiquidateCollateralPaused(aDai, true);
        assertTrue(lens.getMarketPauseStatus(aDai).isLiquidateCollateralPaused);
    }

    function testGetMarketPauseStatusesPauseLiquidateOnBorrow() public {
        morpho.setIsLiquidateBorrowPaused(aDai, true);
        assertTrue(lens.getMarketPauseStatus(aDai).isLiquidateBorrowPaused);
    }

    function testPoolIndexGrowthInsideBlock() public {
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 10 ether);

        uint256 poolSupplyIndexBefore = lens.getIndexes(aDai).poolSupplyIndex;

        FlashLoan flashLoan = new FlashLoan(pool);
        vm.prank(address(supplier2));
        ERC20(dai).transfer(address(flashLoan), 10_000 ether); // To pay the premium.
        flashLoan.callFlashLoan(dai, 10_000 ether);

        uint256 poolSupplyIndexAfter = lens.getIndexes(aDai).poolSupplyIndex;

        assertGt(poolSupplyIndexAfter, poolSupplyIndexBefore);
    }

    function testP2PIndexGrowthInsideBlock() public {
        borrower1.approve(dai, type(uint256).max);
        borrower1.supply(aDai, 10 ether);
        borrower1.borrow(aDai, 5 ether);
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 3e6, 0);
        // Create delta.
        borrower1.repay(aDai, type(uint256).max);

        uint256 p2pSupplyIndexBefore = lens.getCurrentP2PSupplyIndex(aDai);

        FlashLoan flashLoan = new FlashLoan(pool);
        vm.prank(address(supplier2));
        ERC20(dai).transfer(address(flashLoan), 10_000 ether); // To pay the premium.
        flashLoan.callFlashLoan(dai, 10_000 ether);

        uint256 p2pSupplyIndexAfter = lens.getCurrentP2PSupplyIndex(aDai);

        assertGt(p2pSupplyIndexAfter, p2pSupplyIndexBefore);
    }
}
