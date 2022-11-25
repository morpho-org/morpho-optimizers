// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestUpgradeDeltas is TestSetup {
    using WadRayMath for uint256;

    function _onSetUp() internal override {
        super._onSetUp();

        _upgrade();
    }

    function testShouldClearP2PCRV() public {
        (, , uint256 p2pSupplyAmountBefore, uint256 p2pBorrowAmountBefore) = morpho.deltas(aCrv);

        vm.prank(morphoDao);
        morpho.increaseP2PDeltas(aCrv, type(uint256).max);

        uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aCrv);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aCrv);
        uint256 poolSupplyIndex = pool.getReserveNormalizedIncome(crv);
        uint256 poolBorrowIndex = pool.getReserveNormalizedVariableDebt(crv);

        (
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta,
            uint256 p2pSupplyAmountAfter,
            uint256 p2pBorrowAmountAfter
        ) = morpho.deltas(aCrv);

        assertApproxEqAbs(
            p2pSupplyDelta.rayMul(poolSupplyIndex),
            p2pSupplyAmountBefore.rayMul(p2pSupplyIndex),
            10,
            "p2p supply delta"
        );
        assertApproxEqAbs(
            p2pBorrowDelta.rayMul(poolBorrowIndex),
            p2pBorrowAmountBefore.rayMul(p2pBorrowIndex),
            10,
            "p2p borrow delta"
        );
        assertEq(p2pSupplyAmountAfter, p2pSupplyAmountBefore, "p2p supply amount");
        assertEq(p2pBorrowAmountAfter, p2pBorrowAmountBefore, "p2p borrow amount");

        (uint256 avgSupplyRatePerYear, , ) = lens.getAverageSupplyRatePerYear(aCrv);
        (uint256 avgBorrowRatePerYear, , ) = lens.getAverageBorrowRatePerYear(aCrv);
        DataTypes.ReserveData memory reserve = pool.getReserveData(crv);

        assertEq(avgSupplyRatePerYear, reserve.currentLiquidityRate, "avg supply rate per year");
        assertEq(
            avgBorrowRatePerYear,
            reserve.currentVariableBorrowRate,
            "avg borrow rate per year"
        );
    }
}
