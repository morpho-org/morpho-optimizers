// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestP2PDisable is TestSetup {
    function testShouldMatchSupplyDeltaWithP2PDisabled() public {
        uint256 nSuppliers = 3;
        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = nSuppliers * suppliedAmount;
        uint256 collateralAmount = 2 * borrowedAmount;

        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(aUsdc, to6Decimals(collateralAmount));
        borrower1.borrow(aDai, borrowedAmount);

        for (uint256 i; i < nSuppliers; i++) {
            suppliers[i].approve(dai, type(uint256).max);
            suppliers[i].supply(aDai, suppliedAmount);
        }

        // Create delta.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 3e6, 0);
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        // Delta must be greater than 0.
        (uint256 p2pSupplyDelta, , , ) = morpho.deltas(aDai);
        assertGt(p2pSupplyDelta, 0);

        morpho.setIsP2PDisabled(aDai, true);

        // The delta should not be reduced.
        borrower1.borrow(aDai, borrowedAmount);
        (uint256 newP2PSupplyDelta, , , ) = morpho.deltas(aDai);
        assertEq(newP2PSupplyDelta, p2pSupplyDelta);
        // Borrower1 should not be matched P2P.
        (uint256 inP2P, ) = morpho.borrowBalanceInOf(aDai, address(borrower1));
        assertEq(inP2P, 0);
    }

    function testShouldMatchBorrowDeltaWithP2PDisabled() public {
        uint256 nBorrowers = 3;
        uint256 borrowAmount = 1 ether;
        uint256 collateralAmount = 2 * borrowAmount;
        uint256 supplyAmount = nBorrowers * borrowAmount;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(aUsdc, to6Decimals(supplyAmount));

        for (uint256 i; i < nBorrowers; i++) {
            borrowers[i].approve(dai, type(uint256).max);
            borrowers[i].approve(usdc, type(uint256).max);
            borrowers[i].supply(aDai, collateralAmount);
            borrowers[i].borrow(aUsdc, to6Decimals(borrowAmount));
        }

        // Create delta.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 3e6);
        supplier1.withdraw(aUsdc, type(uint256).max);

        // Delta must be greater than 0.
        (, uint256 p2pBorrowDelta, , ) = morpho.deltas(aUsdc);
        assertGt(p2pBorrowDelta, 0);

        morpho.setIsP2PDisabled(aUsdc, true);

        // The delta should not be reduced.
        supplier1.supply(aUsdc, to6Decimals(supplyAmount * 2));
        (, uint256 newP2PBorrowDelta, , ) = morpho.deltas(aUsdc);
        assertEq(newP2PBorrowDelta, p2pBorrowDelta);
        // Supplier1 should not be matched P2P.
        (uint256 inP2P, ) = morpho.supplyBalanceInOf(aUsdc, address(supplier1));
        assertEq(inP2P, 0);
    }

    function testShouldBeAbleToWithdrawRepayAfterPoolPause() public {
        uint256 amount = 100_000 ether;

        // Create some peer-to-peer matching.
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, amount);
        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(aUsdc, to6Decimals(amount * 2));
        borrower1.borrow(aDai, amount);

        // Increase deltas.
        morpho.increaseP2PDeltas(aDai, type(uint256).max);

        // Pause borrow on pool.
        vm.prank(poolAddressesProvider.getPoolAdmin());
        lendingPoolConfigurator.freezeReserve(dai);
        vm.expectRevert();
        supplier1.aaveSupply(dai, 10);
        vm.expectRevert();
        supplier1.aaveBorrow(dai, 10);

        // Withdraw and repay peer-to-peer matched positions.
        supplier1.withdraw(aDai, type(uint256).max);
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);
    }
}
