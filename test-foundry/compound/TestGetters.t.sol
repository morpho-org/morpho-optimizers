// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestGetters is TestSetup {
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

        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_IN_P2P));
        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_ON_POOL));
        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.BORROWERS_IN_P2P));
        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.BORROWERS_ON_POOL));

        borrower1.borrow(cDai, toBorrow);

        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_IN_P2P));
        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_ON_POOL));
        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.BORROWERS_IN_P2P));
        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.BORROWERS_ON_POOL));

        borrower1.borrow(cUsdc, to6Decimals(toBorrow));

        assertEq(address(borrower1), morpho.getHead(cUsdc, Types.PositionType.BORROWERS_ON_POOL));
    }

    function testGetNext() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 10;

        uint256 maxSortedUsers = 10;
        morpho.setMaxSortedUsers(maxSortedUsers);
        createSigners(maxSortedUsers);
        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].approve(dai, amount - i * 1e18);
            borrowers[i].supply(cDai, amount - i * 1e18);
            borrowers[i].borrow(cUsdc, to6Decimals(toBorrow - i * 1e18));
        }

        address nextSupplyOnPool = address(borrowers[0]);
        address nextBorrowOnPool = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyOnPool = morpho.getNext(
                cDai,
                Types.PositionType.SUPPLIERS_ON_POOL,
                nextSupplyOnPool
            );
            nextBorrowOnPool = morpho.getNext(
                cUsdc,
                Types.PositionType.BORROWERS_ON_POOL,
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
            nextSupplyInP2P = morpho.getNext(
                cUsdc,
                Types.PositionType.SUPPLIERS_IN_P2P,
                nextSupplyInP2P
            );
            nextBorrowInP2P = morpho.getNext(
                cDai,
                Types.PositionType.BORROWERS_IN_P2P,
                nextBorrowInP2P
            );

            assertEq(address(suppliers[i + 1]), nextSupplyInP2P);
            assertEq(address(borrowers[i + 1]), nextBorrowInP2P);
        }
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

        Types.AssetLiquidityData memory assetDatacDai = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cDai,
            oracle
        );

        Types.AssetLiquidityData memory assetDatacUsdc = lens.getUserLiquidityDataForAsset(
            address(borrower1),
            cUsdc,
            oracle
        );

        // Avoid stack too deep error.
        Types.AssetLiquidityData memory expectedDatcUsdc;
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
        Types.AssetLiquidityData memory expectedDatacDai;

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

    function testEnteredMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(cDai, 10 ether);

        borrower1.approve(usdc, to6Decimals(10 ether));
        borrower1.supply(cUsdc, to6Decimals(10 ether));

        assertEq(morpho.enteredMarkets(address(borrower1), 0), cDai);
        assertEq(morpho.enteredMarkets(address(borrower1), 1), cUsdc);

        // Borrower1 withdraw, USDC should be the first in enteredMarkets.
        borrower1.withdraw(cDai, type(uint256).max);

        assertEq(morpho.enteredMarkets(address(borrower1), 0), cUsdc);
    }

    function testFailUserLeftMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(cDai, 10 ether);

        // Check that borrower1 entered Dai market.
        assertEq(morpho.enteredMarkets(address(borrower1), 0), cDai);

        // Borrower1 withdraw everything from the Dai market.
        borrower1.withdraw(cDai, 10 ether);

        // Test should fail because there is no element in the array.
        morpho.enteredMarkets(address(borrower1), 0);
    }

    function testGetAllMarkets() public {
        address[] memory allMarkets = morpho.getAllMarkets();

        for (uint256 i; i < pools.length; i++) {
            assertEq(allMarkets[i], pools[i]);
        }
    }
}
