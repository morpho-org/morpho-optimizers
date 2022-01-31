// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/libraries/aave/WadRayMath.sol";

import "./utils/TestSetup.sol";

contract TestFees is TestSetup {
    using WadRayMath for uint256;

    // Should not be possible to set the fee factor higher than 100%
    function test_higher_than_max_fees() public {
        marketsManager.setReserveFactor(10_001);
        testEquality(marketsManager.reserveFactor(), 10_000);
    }

    // Only MarketsManager owner can set the treasury vault
    function test_non_market_manager_cant_set_vault() public {
        hevm.expectRevert(abi.encodeWithSignature("OnlyMarketsManagerOwner()"));
        supplier1.setTreasuryVault(address(borrower1));
    }

    // DAO should be able to claim fees
    function test_claim_fees() public {
        marketsManager.setReserveFactor(1000); // 10%

        // Increase time so that rates update
        hevm.warp(block.timestamp + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 * WAD);
        supplier1.borrow(aDai, 50 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);
        positionsManager.claimToTreasury(aDai);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());

        assertLt(balanceBefore, balanceAfter);
    }

    // DAO should not collect fees when factor is null
    function test_claim_nothing() public {
        marketsManager.setReserveFactor(0);

        // Increase time so that rates update
        hevm.warp(block.timestamp + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(positionsManager.treasuryVault());
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 100 * WAD);
        supplier1.borrow(aDai, 50 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.repay(aDai, type(uint256).max);
        positionsManager.claimToTreasury(aDai);
        uint256 balanceAfter = IERC20(dai).balanceOf(positionsManager.treasuryVault());

        testEquality(balanceBefore, balanceAfter);
    }

    // Suppliers should not earn interests when DAO collect 100% fees
    function test_supplier_gains_with_max_fees() public {
        marketsManager.setReserveFactor(10_000); // 100%

        // Increase time so that rates update
        hevm.warp(block.timestamp + 1);

        uint256 balanceBefore = IERC20(dai).balanceOf(address(supplier1));
        supplier1.approve(dai, type(uint256).max);
        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(aUsdc, 200 * WAD);
        borrower1.borrow(aDai, 100 * WAD);
        supplier1.supply(aDai, 100 * WAD);

        hevm.warp(block.timestamp + (365 days));

        supplier1.withdraw(aDai, type(uint256).max);
        uint256 balanceAfter = IERC20(dai).balanceOf(address(supplier1));

        testEquality(balanceBefore, balanceAfter);
    }
}
