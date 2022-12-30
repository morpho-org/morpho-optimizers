// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestP2PDisable is TestSetup {
    function testShouldNotMatchSupplyDeltaWithP2PDisabled() public {
        uint256 nSuppliers = 3;
        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = nSuppliers * suppliedAmount;
        uint256 collateralAmount = 2 * borrowedAmount;

        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(cUsdc, to6Decimals(collateralAmount));
        borrower1.borrow(cDai, borrowedAmount);

        for (uint256 i; i < nSuppliers; i++) {
            suppliers[i].approve(dai, type(uint256).max);
            suppliers[i].supply(cDai, suppliedAmount);
        }

        moveOneBlockForwardBorrowRepay();

        // Create delta.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 3e6, 0);
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        // Delta must be greater than 0.
        (uint256 p2pSupplyDelta, , , ) = morpho.deltas(cDai);
        assertGt(p2pSupplyDelta, 0);

        morpho.setIsP2PDisabled(cDai, true);

        // The delta should not be reduced.
        borrower1.borrow(cDai, borrowedAmount);
        (uint256 newP2PSupplyDelta, , , ) = morpho.deltas(cDai);
        assertEq(newP2PSupplyDelta, p2pSupplyDelta);
        // Borrower1 should not be matched P2P.
        (uint256 inP2P, ) = morpho.borrowBalanceInOf(cDai, address(borrower1));
        assertEq(inP2P, 0);
    }

    function testShouldNotMatchBorrowDeltaWithP2PDisabled() public {
        uint256 nBorrowers = 3;
        uint256 borrowAmount = 1 ether;
        uint256 collateralAmount = 2 * borrowAmount;
        uint256 supplyAmount = nBorrowers * borrowAmount;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(cUsdc, to6Decimals(supplyAmount));

        for (uint256 i; i < nBorrowers; i++) {
            borrowers[i].approve(dai, type(uint256).max);
            borrowers[i].approve(usdc, type(uint256).max);
            borrowers[i].supply(cDai, collateralAmount);
            borrowers[i].borrow(cUsdc, to6Decimals(borrowAmount));
        }

        // Create delta.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 3e6);
        supplier1.withdraw(cUsdc, type(uint256).max);

        // Delta must be greater than 0.
        (, uint256 p2pBorrowDelta, , ) = morpho.deltas(cUsdc);
        assertGt(p2pBorrowDelta, 0);

        morpho.setIsP2PDisabled(cUsdc, true);

        // The delta should not be reduced.
        supplier1.supply(cUsdc, to6Decimals(supplyAmount * 2));
        (, uint256 newP2PBorrowDelta, , ) = morpho.deltas(cUsdc);
        assertEq(newP2PBorrowDelta, p2pBorrowDelta);
        // Supplier1 should not be matched P2P.
        (uint256 inP2P, ) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));
        assertApproxEqAbs(inP2P, 0, 1e4);
    }

    function testShouldBeAbleToWithdrawRepayAfterPoolPause() public {
        uint256 amount = 100_000 ether;

        // Create some peer-to-peer matching.
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, amount);
        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(cUsdc, to6Decimals(amount * 2));
        borrower1.borrow(cDai, amount);

        // Increase deltas.
        morpho.increaseP2PDeltas(cDai, type(uint256).max);

        // Pause borrow on pool.
        vm.prank(comptroller.admin());
        comptroller._setMintPaused(ICToken(cDai), true);
        vm.prank(comptroller.admin());
        comptroller._setBorrowPaused(ICToken(cDai), true);

        // Withdraw and repay peer-to-peer matched positions.
        supplier1.withdraw(cDai, amount - 1e9);
        // Bypass the borrow repay in the same block by overwritting the storage slot lastBorrowBlock[borrower1].
        hevm.store(address(morpho), keccak256(abi.encode(address(borrower1), 178)), 0);
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);
    }
}
