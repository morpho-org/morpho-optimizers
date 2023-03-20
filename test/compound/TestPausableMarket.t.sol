// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    using CompoundMath for uint256;

    address[] public cEthArray = [cEth];
    address[] public cDaiArray = [cDai];
    uint256[] public amountArray = [1 ether];

    function testAllMarketsPauseUnpause() public {
        morpho.setIsPausedForAllMarkets(true);

        for (uint256 i; i < pools.length; ++i) {
            (
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.marketPauseStatus(pools[i]);
            assertTrue(isSupplyPaused);
            assertTrue(isBorrowPaused);
            assertTrue(isWithdrawPaused);
            assertTrue(isRepayPaused);
            assertTrue(isLiquidateCollateralPaused);
            assertTrue(isLiquidateBorrowPaused);
        }

        morpho.setIsPausedForAllMarkets(false);

        for (uint256 i; i < pools.length; ++i) {
            (
                bool isSupplyPaused,
                bool isBorrowPaused,
                bool isWithdrawPaused,
                bool isRepayPaused,
                bool isLiquidateCollateralPaused,
                bool isLiquidateBorrowPaused,

            ) = morpho.marketPauseStatus(pools[i]);
            assertFalse(isSupplyPaused);
            assertFalse(isBorrowPaused);
            assertFalse(isWithdrawPaused);
            assertFalse(isRepayPaused);
            assertFalse(isLiquidateCollateralPaused);
            assertFalse(isLiquidateBorrowPaused);
        }
    }

    function testShouldDisableAllMarketsWhenGloballyPaused() public {
        morpho.setIsPausedForAllMarkets(true);

        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            hevm.expectRevert(abi.encodeWithSignature("SupplyIsPaused()"));
            supplier1.supply(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("BorrowIsPaused()"));
            supplier1.borrow(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("WithdrawIsPaused()"));
            supplier1.withdraw(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("RepayIsPaused()"));
            supplier1.repay(pools[i], 1);

            hevm.expectRevert(abi.encodeWithSignature("LiquidateCollateralIsPaused()"));
            supplier1.liquidate(pools[i], pools[0], address(supplier1), 1);
        }
    }

    function testBorrowPauseCheckSkipped() public {
        // Deprecate a market.
        morpho.setIsBorrowPaused(cDai, true);
        morpho.setIsDeprecated(cDai, true);
        (, bool isBorrowPaused, , , , , bool isDeprecated) = morpho.marketPauseStatus(cDai);

        assertTrue(isBorrowPaused);
        assertTrue(isDeprecated);

        morpho.setIsPausedForAllMarkets(false);
        (, isBorrowPaused, , , , , isDeprecated) = morpho.marketPauseStatus(cDai);

        assertTrue(isBorrowPaused);
        assertTrue(isDeprecated);

        morpho.setIsPausedForAllMarkets(true);
        (, isBorrowPaused, , , , , isDeprecated) = morpho.marketPauseStatus(cDai);

        assertTrue(isBorrowPaused);
        assertTrue(isDeprecated);
    }

    function testOnlyOwnerShouldDisableSupply() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsSupplyPaused(cDai, true);

        morpho.setIsSupplyPaused(cDai, true);

        vm.expectRevert(abi.encodeWithSignature("SupplyIsPaused()"));
        supplier1.supply(cDai, amount);
    }

    function testOnlyOwnerShouldDisableBorrow() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsBorrowPaused(cDai, true);

        morpho.setIsBorrowPaused(cDai, true);

        vm.expectRevert(abi.encodeWithSignature("BorrowIsPaused()"));
        supplier1.borrow(cDai, amount);
    }

    function testOnlyOwnerShouldDisableWithdraw() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsWithdrawPaused(cDai, true);

        morpho.setIsWithdrawPaused(cDai, true);

        vm.expectRevert(abi.encodeWithSignature("WithdrawIsPaused()"));
        supplier1.withdraw(cDai, amount);
    }

    function testOnlyOwnerShouldDisableRepay() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsRepayPaused(cDai, true);

        morpho.setIsRepayPaused(cDai, true);

        vm.expectRevert(abi.encodeWithSignature("RepayIsPaused()"));
        supplier1.repay(cDai, amount);
    }

    function testOnlyOwnerShouldDisableLiquidateOnCollateral() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateCollateralPaused(cDai, true);

        morpho.setIsLiquidateCollateralPaused(cDai, true);

        vm.expectRevert(abi.encodeWithSignature("LiquidateCollateralIsPaused()"));
        supplier1.liquidate(cUsdc, cDai, address(supplier2), amount);
    }

    function testOnlyOwnerShouldDisableLiquidateOnBorrow() public {
        uint256 amount = 10_000 ether;

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateBorrowPaused(cDai, true);

        morpho.setIsLiquidateBorrowPaused(cDai, true);

        vm.expectRevert(abi.encodeWithSignature("LiquidateBorrowIsPaused()"));
        supplier1.liquidate(cDai, cUsdc, address(supplier2), amount);
    }
}
