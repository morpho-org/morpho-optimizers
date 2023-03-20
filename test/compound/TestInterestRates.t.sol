// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/compound/InterestRatesManager.sol";
import "@forge-std/Test.sol";

contract TestInterestRates is InterestRatesManager, Test {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public p2pSupplyIndexTest = 1 * WAD;
    uint256 public p2pBorrowIndexTest = 1 * WAD;
    uint256 public poolSupplyIndexTest = 2 * WAD;
    uint256 public poolBorrowIndexTest = 3 * WAD;
    Types.LastPoolIndexes public lastPoolIndexesTest =
        Types.LastPoolIndexes(uint32(block.number), uint112(1 * WAD), uint112(1 * WAD));
    uint256 public reserveFactor0PerCentTest = 0;
    uint256 public reserveFactor50PerCentTest = 5_000;
    uint256 public p2pIndexCursorTest = 3_333;

    // prettier-ignore
    function computeP2PIndexes(InterestRatesManager.Params memory _params)
        public
        pure
        returns (uint256 p2pSupplyIndex_, uint256 p2pBorrowIndex_)
    {
        uint256 poolSupplyGrowthFactor = ((_params.poolSupplyIndex * WAD) / _params.lastPoolIndexes.lastSupplyPoolIndex);
        uint256 poolBorrowGrowthFactor = ((_params.poolBorrowIndex * WAD) / _params.lastPoolIndexes.lastBorrowPoolIndex);
        uint256 p2pGrowthFactor = ((PercentageMath.PERCENTAGE_FACTOR - _params.p2pIndexCursor) * poolSupplyGrowthFactor + _params.p2pIndexCursor * poolBorrowGrowthFactor) / PercentageMath.PERCENTAGE_FACTOR;
        uint256 shareOfTheSupplyDelta = _params.delta.p2pBorrowAmount > 0
            ? (((_params.delta.p2pSupplyDelta * _params.lastPoolIndexes.lastSupplyPoolIndex) / WAD) * WAD) /
                ((_params.delta.p2pSupplyAmount * _params.lastP2PSupplyIndex) / WAD)
            : 0;
        uint256 shareOfTheBorrowDelta = _params.delta.p2pSupplyAmount > 0
            ? (((_params.delta.p2pBorrowDelta * _params.lastPoolIndexes.lastBorrowPoolIndex) / WAD) * WAD) /
                ((_params.delta.p2pBorrowAmount * _params.lastP2PBorrowIndex) / WAD)
            : 0;
        if (poolSupplyGrowthFactor <= poolBorrowGrowthFactor) {
            uint256 p2pSupplyGrowthFactor = (p2pGrowthFactor - (_params.reserveFactor * (p2pGrowthFactor - poolSupplyGrowthFactor) / PercentageMath.PERCENTAGE_FACTOR));
            uint256 p2pBorrowGrowthFactor = (p2pGrowthFactor + (_params.reserveFactor * (poolBorrowGrowthFactor - p2pGrowthFactor) / PercentageMath.PERCENTAGE_FACTOR));
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
            lastPoolIndexesTest,
            reserveFactor0PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithReserveFactor() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolIndexesTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithDelta() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolIndexesTest,
            reserveFactor0PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWithDeltaAndReserveFactor() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolSupplyIndexTest,
            poolBorrowIndexTest,
            lastPoolIndexesTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWhenPoolSupplyIndexHasJumpedWithoutDelta() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolBorrowIndexTest * 2,
            poolBorrowIndexTest,
            lastPoolIndexesTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(0, 0, 0, 0)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }

    function testIndexComputationWhenPoolSupplyIndexHasJumpedWithDelta() public {
        InterestRatesManager.Params memory params = InterestRatesManager.Params(
            p2pSupplyIndexTest,
            p2pBorrowIndexTest,
            poolBorrowIndexTest * 2,
            poolBorrowIndexTest,
            lastPoolIndexesTest,
            reserveFactor50PerCentTest,
            p2pIndexCursorTest,
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }
}
