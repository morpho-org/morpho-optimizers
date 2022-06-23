// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/compound/InterestRatesManager.sol";
import "ds-test/test.sol";
import "forge-std/stdlib.sol";

contract TestInterestRates is InterestRatesManager, DSTest {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public p2pSupplyIndexTest = 1 * WAD;
    uint256 public p2pBorrowIndexTest = 1 * WAD;
    uint256 public poolSupplyIndexTest = 2 * WAD;
    uint256 public poolBorrowIndexTest = 3 * WAD;
    uint256 public lastPoolSupplyIndexTest = 1 * WAD;
    uint256 public lastPoolBorrowIndexTest = 1 * WAD;
    uint256 public reserveFactor0PerCentTest = 0;
    uint256 public reserveFactor50PerCentTest = 5_000;
    uint256 public p2pIndexCursorTest = 3_333;

    // prettier-ignore
    function computeP2PIndexes(InterestRatesManager.Params memory _params)
        public
        pure
        returns (uint256 p2pSupplyIndex_, uint256 p2pBorrowIndex_)
    {
        uint256 poolSupplyGrowthFactor = ((_params.poolSupplyIndex * WAD) / _params.lastPoolSupplyIndex);
        uint256 poolBorrowGrowthFactor = ((_params.poolBorrowIndex * WAD) / _params.lastPoolBorrowIndex);
        uint256 p2pGrowthFactor = ((MAX_BASIS_POINTS - _params.p2pIndexCursor) * poolSupplyGrowthFactor + _params.p2pIndexCursor * poolBorrowGrowthFactor) / MAX_BASIS_POINTS;
        uint256 shareOfTheSupplyDelta = _params.delta.p2pBorrowAmount > 0
            ? (((_params.delta.p2pSupplyDelta * _params.lastPoolSupplyIndex) / WAD) * WAD) /
                ((_params.delta.p2pSupplyAmount * _params.lastP2PSupplyIndex) / WAD)
            : 0;
        uint256 shareOfTheBorrowDelta = _params.delta.p2pSupplyAmount > 0
            ? (((_params.delta.p2pBorrowDelta * _params.lastPoolBorrowIndex) / WAD) * WAD) /
                ((_params.delta.p2pBorrowAmount * _params.lastP2PBorrowIndex) / WAD)
            : 0;
        if (poolSupplyGrowthFactor <= poolBorrowGrowthFactor) {
            uint256 p2pSupplyGrowthFactor = (p2pGrowthFactor - (_params.reserveFactor * (p2pGrowthFactor - poolSupplyGrowthFactor) / MAX_BASIS_POINTS));
            uint256 p2pBorrowGrowthFactor = (p2pGrowthFactor + (_params.reserveFactor * (poolBorrowGrowthFactor - p2pGrowthFactor) / MAX_BASIS_POINTS));
            p2pSupplyIndex_ =
                _params.lastP2PSupplyIndex *
                    ((WAD - shareOfTheSupplyDelta) * p2pSupplyGrowthFactor / WAD +
                    (shareOfTheSupplyDelta * poolSupplyGrowthFactor) / WAD) /
                WAD;
            p2pBorrowIndex_ =
                _params.lastP2PBorrowIndex *
                    ((WAD - shareOfTheBorrowDelta) * p2pBorrowGrowthFactor / WAD +
                    (shareOfTheBorrowDelta * poolBorrowGrowthFactor) / WAD) /
                WAD;
        } else {
            p2pSupplyIndex_ =
                _params.lastP2PSupplyIndex * 
                ((WAD - shareOfTheSupplyDelta) * poolBorrowGrowthFactor + shareOfTheSupplyDelta * poolSupplyGrowthFactor) / WAD / WAD;
            p2pBorrowIndex_ = 
                _params.lastP2PBorrowIndex * poolBorrowGrowthFactor / WAD; 
        }

    }

    function testIndexComputation() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor0PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithReserveFactor() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithDelta() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor0PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithDeltaAndReserveFactor() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWhenPoolSupplyIndexHasJumpedWithoutDelta() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolBorrowIndexTest * 2,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWhenPoolSupplyIndexHasJumpedWithDelta() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolBorrowIndexTest * 2,
            poolBorrowIndexTest,
            lastPoolSupplyIndexTest,
            lastPoolBorrowIndexTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEq(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEq(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }
}
