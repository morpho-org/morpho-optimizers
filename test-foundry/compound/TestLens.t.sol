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

    struct UserBalance {
        uint256 onPool;
        uint256 inP2P;
        uint256 totalBalance;
    }

    function testUserLiquidityDataForAssetWithNothing() public {
        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
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

        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
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

        Types.AssetLiquidityData memory assetData = lens.getUserLiquidityDataForAsset(
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
        // Divide and multiply to take into account rounding errors.
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

        Types.AssetLiquidityData memory assetDataCDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            oracle
        );

        // Avoid stack too deep error.
        Types.AssetLiquidityData memory expectedDataCUsdc;
        (, uint256 collateralFactor, ) = comptroller.markets(cUsdc);
        expectedDataCUsdc.underlyingPrice = oracle.getUnderlyingPrice(cUsdc);

        expectedDataCUsdc.debtValue = getBalanceOnCompound(toBorrow, ICToken(cUsdc).borrowIndex())
        .mul(expectedDataCUsdc.underlyingPrice);

        assertEq(
            assetDataCUsdc.underlyingPrice,
            expectedDataCUsdc.underlyingPrice,
            "underlyingPriceUsdc"
        );
        assertEq(assetDataCUsdc.collateralValue, 0, "collateralValue");
        assertEq(assetDataCUsdc.maxDebtValue, 0, "maxDebtValue");
        assertEq(assetDataCUsdc.debtValue, expectedDataCUsdc.debtValue, "debtValueUsdc");

        // Avoid stack too deep error.
        Types.AssetLiquidityData memory expectedDataCDai;

        (, expectedDataCDai.collateralFactor, ) = comptroller.markets(cDai);

        expectedDataCDai.underlyingPrice = oracle.getUnderlyingPrice(cDai);
        expectedDataCDai.collateralValue = getBalanceOnCompound(
            amount,
            ICToken(cDai).exchangeRateStored()
        ).mul(expectedDataCDai.underlyingPrice);
        expectedDataCDai.maxDebtValue = expectedDataCDai.collateralValue.mul(
            expectedDataCDai.collateralFactor
        );

        assertEq(assetDataCDai.collateralFactor, collateralFactor, "collateralFactor");
        assertEq(
            assetDataCDai.underlyingPrice,
            expectedDataCDai.underlyingPrice,
            "underlyingPriceDai"
        );

        assertEq(
            assetDataCDai.collateralValue,
            expectedDataCDai.collateralValue,
            "collateralValueDai"
        );
        assertEq(assetDataCDai.maxDebtValue, expectedDataCDai.maxDebtValue, "maxDebtValueDai");
        assertEq(assetDataCDai.debtValue, 0, "debtValueDai");
    }

    function testGetterUserWithNothing() public {
        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        assertEq(withdrawable, 0);
        assertEq(borrowable, 0);
    }

    function testMaxCapacitiesWithSupply() public {
        uint256 amount = to6Decimals(10000 ether);

        borrower1.approve(usdc, amount);
        borrower1.supply(cUsdc, amount);

        Types.AssetLiquidityData memory assetDataCUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        uint256 expectedBorrowableUsdc = assetDataCUsdc.maxDebtValue.div(
            assetDataCUsdc.underlyingPrice
        );
        uint256 expectedBorrowableDai = assetDataCUsdc.maxDebtValue.div(
            assetDataCDai.underlyingPrice
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

    function testUserBalanceWithoutMatching() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        UserBalance memory userSupplyBalance;

        (userSupplyBalance.onPool, userSupplyBalance.inP2P, userSupplyBalance.totalBalance) = lens
        .getUserSupplyBalance(address(borrower1), cDai);

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.mul(morpho.p2pSupplyIndex(cDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.mul(
            ICToken(cDai).exchangeRateCurrent()
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

        (userBorrowBalance.onPool, userBorrowBalance.inP2P, userBorrowBalance.totalBalance) = lens
        .getUserBorrowBalance(address(borrower1), cUsdc);

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.mul(morpho.p2pBorrowIndex(cUsdc));
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.mul(ICToken(cUsdc).borrowIndex());
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
        borrower1.supply(cDai, amount);
        borrower1.borrow(cUsdc, toBorrow);

        uint256 toMatch = toBorrow / 2;
        supplier1.approve(usdc, toMatch);
        supplier1.supply(cUsdc, toMatch);

        // borrower 1 supply balance (not matched)
        UserBalance memory userSupplyBalance;

        (userSupplyBalance.onPool, userSupplyBalance.inP2P, userSupplyBalance.totalBalance) = lens
        .getUserSupplyBalance(address(borrower1), cDai);

        (uint256 supplyBalanceInP2P, uint256 supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 expectedSupplyBalanceInP2P = supplyBalanceInP2P.mul(morpho.p2pSupplyIndex(cDai));
        uint256 expectedSupplyBalanceOnPool = supplyBalanceOnPool.mul(
            ICToken(cDai).exchangeRateCurrent()
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

        (userBorrowBalance.onPool, userBorrowBalance.inP2P, userBorrowBalance.totalBalance) = lens
        .getUserBorrowBalance(address(borrower1), cUsdc);

        (uint256 borrowBalanceInP2P, uint256 borrowBalanceOnPool) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = borrowBalanceInP2P.mul(morpho.p2pBorrowIndex(cUsdc));
        uint256 expectedBorrowBalanceOnPool = borrowBalanceOnPool.mul(ICToken(cUsdc).borrowIndex());

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
            matchedSupplierSupplyBalance.onPool,
            matchedSupplierSupplyBalance.inP2P,
            matchedSupplierSupplyBalance.totalBalance
        ) = lens.getUserSupplyBalance(address(supplier1), cUsdc);

        (supplyBalanceInP2P, supplyBalanceOnPool) = morpho.supplyBalanceInOf(
            cUsdc,
            address(supplier1)
        );

        expectedSupplyBalanceInP2P = supplyBalanceInP2P.mul(morpho.p2pSupplyIndex(cUsdc));
        expectedSupplyBalanceOnPool = supplyBalanceOnPool.mul(ICToken(cUsdc).exchangeRateCurrent());

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
        borrower1.supply(cUsdc, to6Decimals(amount));
        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        Types.AssetLiquidityData memory assetDataCUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        Types.AssetLiquidityData memory assetDataCUsdt = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdt,
            oracle
        );

        (uint256 withdrawableDai, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);
        (uint256 withdrawableUsdc, ) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdc);
        (, uint256 borrowableUsdt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdt);

        uint256 expectedBorrowableUsdt = (assetDataCDai.maxDebtValue + assetDataCUsdc.maxDebtValue)
        .div(assetDataCUsdt.underlyingPrice);

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

    function testGetMarketData() public {
        (
            uint256 p2pSupplyIndex,
            uint256 p2pBorrowIndex,
            uint32 lastUpdateBlockNumber,
            uint256 p2pSupplyDelta_,
            uint256 p2pBorrowDelta_,
            uint256 p2pSupplyAmount_,
            uint256 p2pBorrowAmount_
        ) = lens.getMarketData(cDai);

        assertEq(p2pSupplyIndex, morpho.p2pSupplyIndex(cDai));
        assertEq(p2pBorrowIndex, morpho.p2pBorrowIndex(cDai));
        (uint32 expectedLastUpdateBlockNumber, , ) = morpho.lastPoolIndexes(cDai);
        assertEq(lastUpdateBlockNumber, expectedLastUpdateBlockNumber);
        (
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount
        ) = morpho.deltas(cDai);

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
            uint256 reserveFactor,
            uint256 collateralFactor
        ) = lens.getMarketConfiguration(cDai);
        assertTrue(underlying == ICToken(cDai).underlying());

        (bool isCreated_, bool isPaused_, bool isPartiallyPaused_) = morpho.marketStatus(cDai);

        assertTrue(isCreated == isCreated_);
        assertTrue(p2pDisabled == morpho.p2pDisabled(cDai));

        assertTrue(isPaused == isPaused_);
        assertTrue(isPartiallyPaused == isPartiallyPaused_);
        (uint16 expectedReserveFactor, ) = morpho.marketParameters(cDai);
        assertTrue(reserveFactor == expectedReserveFactor);
        (, uint256 expectedCollateralFactor, ) = morpho.comptroller().markets(cDai);
        assertTrue(collateralFactor == expectedCollateralFactor);
    }

    function testGetUpdatedIndexes() public {
        hevm.roll(block.number + (24 * 60 * 4));
        (
            uint256 newP2PSupplyIndex,
            uint256 newP2PBorrowIndex,
            uint256 newPoolSupplyIndex,
            uint256 newPoolBorrowIndex
        ) = lens.getUpdatedIndexes(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(cDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(cDai));

        ICToken(cDai).accrueInterest();
        assertEq(newPoolSupplyIndex, ICToken(cDai).exchangeRateCurrent());
        assertEq(newPoolBorrowIndex, ICToken(cDai).borrowIndex());
    }

    function testGetUpdatedP2PIndexes() public {
        hevm.roll(block.number + (24 * 60 * 4));
        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = lens.getUpdatedP2PIndexes(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(cDai));
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(cDai));
    }

    function testGetUpdatedP2PSupplyIndex() public {
        hevm.roll(block.number + (24 * 60 * 4));
        uint256 newP2PSupplyIndex = lens.getUpdatedP2PSupplyIndex(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(newP2PSupplyIndex, morpho.p2pSupplyIndex(cDai));
    }

    function testGetUpdatedP2PBorrowIndex() public {
        hevm.roll(block.number + (24 * 60 * 4));
        uint256 newP2PBorrowIndex = lens.getUpdatedP2PBorrowIndex(cDai);

        morpho.updateP2PIndexes(cDai);
        assertEq(newP2PBorrowIndex, morpho.p2pBorrowIndex(cDai));
    }

    function testGetAllMarkets() public {
        address[] memory lensMarkets = lens.getAllMarkets();
        address[] memory morphoMarkets = morpho.getAllMarkets();

        for (uint256 i; i < lensMarkets.length; i++) {
            assertEq(morphoMarkets[i], lensMarkets[i]);
        }
    }

    function testGetEnteredMarkets() public {
        uint256 amount = 1e12;
        supplier1.approve(dai, amount);
        supplier1.approve(usdc, amount);
        supplier1.approve(usdt, amount);
        supplier1.supply(cDai, amount);
        supplier1.supply(cUsdc, amount);
        supplier1.supply(cUsdt, amount);

        address[] memory lensEnteredMarkets = lens.getEnteredMarkets(address(supplier1));
        address[] memory morphoEnteredMarkets = morpho.getEnteredMarkets(address(supplier1));

        for (uint256 i; i < lensEnteredMarkets.length; i++) {
            assertEq(morphoEnteredMarkets[i], lensEnteredMarkets[i]);
        }
    }

    function testGetRates() public {
        hevm.roll(block.number + 1_000);
        (
            uint256 p2pSupplyRate,
            uint256 p2pBorrowRate,
            uint256 poolSupplyRate,
            uint256 poolBorrowRate
        ) = lens.getRates(cDai);

        (uint256 expectedP2PSupplyRate, uint256 expectedP2PBorrowRate) = getApproxP2PRates(cDai);
        uint256 expectedPoolSupplyRate = ICToken(cDai).supplyRatePerBlock();
        uint256 expectedPoolBorrowRate = ICToken(cDai).borrowRatePerBlock();

        assertEq(p2pSupplyRate, expectedP2PSupplyRate);
        assertEq(p2pBorrowRate, expectedP2PBorrowRate);
        assertEq(poolSupplyRate, expectedPoolSupplyRate);
        assertEq(poolBorrowRate, expectedPoolBorrowRate);
    }

    function testIsLiquidatableFalse() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        assertFalse(lens.isLiquidatable(address(borrower1)));
    }

    function testIsLiquidatableTrue() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(usdc, oracle.getUnderlyingPrice(cUsdc) / 2);

        assertTrue(lens.isLiquidatable(address(borrower1)));
    }

    function testComputeLiquidation() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(usdc, 0);

        assertEq(lens.computeLiquidationAmount(address(borrower1), cDai, cUsdc), 0);
    }

    function testComputeLiquidation2() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        assertApproxEq(
            lens.computeLiquidationAmount(address(borrower1), cDai, cUsdc),
            amount.mul(comptroller.closeFactorMantissa()),
            1
        );
    }

    function testComputeLiquidation3() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        createAndSetCustomPriceOracle().setDirectPrice(
            usdc,
            (oracle.getUnderlyingPrice(cDai) / 2) * 1e12 // Setting the value of the collateral at the same value as the debt.
        );

        assertApproxEq(
            lens.computeLiquidationAmount(address(borrower1), cDai, cUsdc),
            amount / 2,
            1
        );
    }

    function testFuzzLiquidation(uint64 _amount, uint64 _collateralPrice) public {
        uint256 amount = uint256(_amount) + 1e13;
        uint256 collateralPrice = uint256(_collateralPrice) + 1;

        supplier2.approve(usdc, 100e6);
        supplier2.supply(cUsdc, 100e6);

        supplier1.approve(usdc, type(uint256).max);
        uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier1));

        borrower1.approve(dai, 2 * amount);
        borrower1.supply(cDai, 2 * amount);
        borrower1.borrow(cUsdc, to6Decimals(amount));

        createAndSetCustomPriceOracle().setDirectPrice(dai, collateralPrice);

        if (lens.isLiquidatable(address(borrower1))) {
            (uint256 collateralValue, uint256 debtValue, uint256 maxDebtValue) = lens
            .getUserBalanceStates(address(borrower1));
            assertLt(maxDebtValue, debtValue);

            uint256 toRepay = lens.computeLiquidationAmount(address(borrower1), cUsdc, cDai);

            if (toRepay == 0) {
                // assertEq(collateralValue, 0, "collateral value supposed to be 0");
            } else {
                do {
                    supplier1.liquidate(cUsdc, cDai, address(borrower1), toRepay);
                    assertGt(
                        ERC20(dai).balanceOf(address(supplier1)),
                        balanceBefore,
                        "balance did not increase"
                    );
                    balanceBefore = ERC20(dai).balanceOf(address(supplier1));
                    toRepay = lens.computeLiquidationAmount(address(borrower1), cUsdc, cDai);
                } while (lens.isLiquidatable(address(borrower1)) && toRepay > 0);

                if (collateralValue.div(comptroller.liquidationIncentiveMantissa()) > debtValue) {
                    // limit solvent
                    assertFalse(lens.isLiquidatable(address(borrower1)));
                } else {
                    // limit no collateral
                    (collateralValue, , ) = lens.getUserBalanceStates(address(borrower1));
                    // assertEq(collateralValue, 0, "collateralValue != 0");
                }
            }
        }
    }
}
