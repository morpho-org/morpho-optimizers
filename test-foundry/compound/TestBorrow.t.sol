// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestBorrow is TestSetup {
    using CompoundMath for uint256;

    function testBorrow1() public {
        uint256 usdcAmount = to6Decimals(10_000 ether);

        borrower1.approve(usdc, usdcAmount);
        borrower1.supply(cUsdc, usdcAmount);

        (, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);

        hevm.expectRevert(PositionsManager.UnauthorisedBorrow.selector);
        borrower1.borrow(cDai, borrowable + 1e12);
    }

    function testBorrow2() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedOnPool = amount.div(ICToken(cDai).borrowIndex());

        assertEq(onPool, expectedOnPool);
        assertEq(inP2P, 0);
    }

    function testBorrow3() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(amount * 2));
        borrower1.supply(cUsdc, to6Decimals(amount * 2));

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        (, uint256 supplyOnPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        uint256 toBorrow = supplyOnPool.mul(cDaiSupplyIndex);
        borrower1.borrow(cDai, toBorrow);

        (uint256 supplyInP2P, ) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiSupplyIndex).div(
            p2pBorrowIndex
        );
        uint256 expectedSupplyInP2P = expectedBorrowInP2P;

        assertEq(supplyInP2P, expectedSupplyInP2P, "Supplier1 in peer-to-peer");

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        assertEq(onPool, 0, "Borrower1 on pool");
        assertEq(inP2P, expectedBorrowInP2P, "Borrower1 in peer-to-peer");
    }

    function testBorrow4() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));
        uint256 borrowAmount = amount * 2;

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, borrowAmount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiSupplyIndex).div(
            morpho.p2pBorrowIndex(cDai)
        );
        uint256 expectedBorrowOnPool = (borrowAmount -
            getBalanceOnCompound(amount, cDaiSupplyIndex))
        .div(ICToken(cDai).borrowIndex());

        assertEq(inP2P, expectedBorrowInP2P, "Borrower1 in peer-to-peer");
        assertEq(onPool, expectedBorrowOnPool, "Borrower1 on pool");
    }

    function testBorrow5() public {
        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 5;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / NMAX;
        uint256[] memory rates = new uint256[](NMAX);
        uint256 toBorrow;

        for (uint256 i = 0; i < NMAX; i++) {
            // Rates change every time.
            rates[i] = ICToken(cDai).exchangeRateCurrent();
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);

            (, uint256 supplyOnPool) = morpho.supplyBalanceInOf(cDai, address(supplier1));
            toBorrow += supplyOnPool.mul(rates[i]);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, toBorrow);
        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
        uint256 inP2P;
        uint256 onPool;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));

            assertEq(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(p2pSupplyIndex),
                "in peer-to-peer"
            );
            assertEq(onPool, 0, "on pool");
        }

        (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiSupplyIndex).div(
            morpho.p2pBorrowIndex(cDai)
        );

        assertApproxEq(inP2P, expectedBorrowInP2P, 1, "Borrower1 in peer-to-peer");
        assertEq(onPool, 0, "Borrower1 on pool");
    }

    function testBorrow6() public {
        setMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint256 NMAX = 5;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / (2 * NMAX);
        uint256[] memory rates = new uint256[](NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            // Rates change every time.
            rates[i] = ICToken(cDai).exchangeRateCurrent();
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        uint256 cDaiSupplyIndex = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 matchedAmount;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));

            assertEq(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(morpho.p2pSupplyIndex(cDai)),
                "in peer-to-peer"
            );
            assertEq(onPool, 0, "on pool");

            matchedAmount += getBalanceOnCompound(amountPerSupplier, cDaiSupplyIndex);
        }

        (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount / 2, cDaiSupplyIndex).div(
            morpho.p2pBorrowIndex(cDai)
        );
        uint256 expectedBorrowOnPool = (amount - matchedAmount).div(borrowIndex);

        assertApproxEq(inP2P, expectedBorrowInP2P, 5, "Borrower1 in peer-to-peer");
        assertEq(onPool, expectedBorrowOnPool, "Borrower1 on pool");
    }

    function testBorrowMultipleAssets() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, address(morpho), to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));

        borrower1.borrow(cDai, amount);
        borrower1.borrow(cDai, amount);

        (, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedOnPool = (2 * amount).div(ICToken(cDai).borrowIndex());
        assertEq(onPool, expectedOnPool);
    }

    function testBorrowOnPoolThreshold() public {
        uint256 amountBorrowed = 1;

        borrower1.approve(usdc, to6Decimals(1 ether));
        borrower1.supply(cUsdc, to6Decimals(1 ether));

        // We check that borrowing any amount accrue the debt.
        borrower1.borrow(cDai, amountBorrowed);
        (, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        assertEq(onPool, ICToken(cDai).balanceOf(address(morpho)));
        assertEq(
            ICToken(cDai).borrowBalanceCurrent(address(morpho)),
            amountBorrowed,
            "borrow balance"
        );
    }
}
