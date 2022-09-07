// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    address[] public aDaiArray = [aDai];
    address[] public aAaveArray = [aAave];
    uint256[] public amountArray = [1 ether];

    function testOnlyOwnerShouldTriggerPauseFunction() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setPauseStatus(aDai, true, true, true, true, true);

        morpho.setPauseStatus(aDai, true, true, true, true, true);
        (
            ,
            ,
            ,
            ,
            ,
            bool isSupplyPaused,
            bool isBorrowPaused,
            bool isWithdrawPaused,
            bool isRepayPaused,
            bool isLiquidatePaused
        ) = morpho.market(aDai);
        assertTrue(isSupplyPaused);
        assertTrue(isBorrowPaused);
        assertTrue(isWithdrawPaused);
        assertTrue(isRepayPaused);
        assertTrue(isLiquidatePaused);
    }

    function testAllMarketsPauseUnpause() public {
        morpho.setPauseStatusForAllMarkets(true);

        for (uint256 i; i < pools.length; ++i) {
            (
                ,
                ,
                ,
                ,
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidatePaused
            ) = morpho.market(pools[i]);
            assertTrue(isSupplyPaused);
            assertTrue(isBorrowPaused);
            assertTrue(isWithdrawPaused);
            assertTrue(isRepayPaused);
            assertTrue(isLiquidatePaused);
        }

        morpho.setPauseStatusForAllMarkets(false);

        for (uint256 i; i < pools.length; ++i) {
            (
                ,
                ,
                ,
                ,
                ,
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidatePaused
            ) = morpho.market(pools[i]);
            assertFalse(isSupplyPaused);
            assertFalse(isBorrowPaused);
            assertFalse(isWithdrawPaused);
            assertFalse(isRepayPaused);
            assertFalse(isLiquidatePaused);
        }
    }

    function testPauseUnpause() public {
        morpho.setPauseStatus(aDai, true, true, true, true, true);
        (
            ,
            ,
            ,
            ,
            ,
            bool isSupplyPaused,
            bool isBorrowPaused,
            bool isWithdrawPaused,
            bool isRepayPaused,
            bool isLiquidatePaused
        ) = morpho.market(aDai);
        assertTrue(isSupplyPaused);
        assertTrue(isBorrowPaused);
        assertTrue(isWithdrawPaused);
        assertTrue(isRepayPaused);
        assertTrue(isLiquidatePaused);

        morpho.setPauseStatus(aDai, false, false, false, false, false);
        (
            ,
            ,
            ,
            ,
            ,
            isSupplyPaused,
            isBorrowPaused,
            isWithdrawPaused,
            isRepayPaused,
            isLiquidatePaused
        ) = morpho.market(aDai);
        assertFalse(isSupplyPaused);
        assertFalse(isBorrowPaused);
        assertFalse(isWithdrawPaused);
        assertFalse(isRepayPaused);
        assertFalse(isLiquidatePaused);
    }

    function testShouldTriggerFunctionsWhenNotPaused() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = to6Decimals(amount / 2);

        supplier1.approve(dai, amount);
        supplier1.supply(aDai, amount);

        supplier1.borrow(aUsdc, toBorrow);

        supplier1.approve(usdc, toBorrow);
        supplier1.repay(aUsdc, toBorrow);

        (, toBorrow) = lens.getUserMaxCapacitiesForAsset(address(supplier1), aUsdc);
        supplier1.borrow(aUsdc, toBorrow);

        // Change Oracle
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getAssetPrice(dai) * 93) / 100);

        uint256 toLiquidate = toBorrow / 2;
        User liquidator = borrower3;
        liquidator.approve(usdc, toLiquidate);
        liquidator.liquidate(aUsdc, aDai, address(supplier1), toLiquidate);

        supplier1.withdraw(aDai, 1);

        morpho.claimToTreasury(aDaiArray, amountArray);
    }

    function testShouldDisableAllMarketsWhenGloballyPaused() public {
        morpho.setPauseStatusForAllMarkets(true);

        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.supply(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.borrow(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.withdraw(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.repay(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.liquidate(pools[i], pools[0], address(supplier1), 1);

            hevm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
            supplier1.liquidate(pools[0], pools[i], address(supplier1), 1);
        }
    }

    function testShouldDisableSupply() public {
        uint256 amount = 10_000 ether;

        morpho.setPauseStatus(aDai, true, false, false, false, false);

        vm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.supply(aDai, amount);
    }

    function testShouldDisableBorrow() public {
        uint256 amount = 10_000 ether;

        morpho.setPauseStatus(aDai, false, true, false, false, false);

        vm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.borrow(aDai, amount);
    }

    function testShouldDisableWithdraw() public {
        uint256 amount = 10_000 ether;

        morpho.setPauseStatus(aDai, false, false, true, false, false);

        vm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.withdraw(aDai, amount);
    }

    function testShouldDisableRepay() public {
        uint256 amount = 10_000 ether;

        morpho.setPauseStatus(aDai, false, false, false, true, false);

        vm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.repay(aDai, amount);
    }

    function testShouldDisableLiquidateOnBorrow() public {
        uint256 amount = 10_000 ether;

        morpho.setPauseStatus(aDai, false, false, false, false, true);

        vm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.liquidate(aDai, aUsdc, address(supplier2), amount);
    }

    function testShouldDisableLiquidateOnCollateral() public {
        uint256 amount = 10_000 ether;

        morpho.setPauseStatus(aDai, false, false, true, false, false);

        vm.expectRevert(abi.encodeWithSignature("MarketPaused()"));
        supplier1.liquidate(aUsdc, aDai, address(supplier2), amount);
    }
}
