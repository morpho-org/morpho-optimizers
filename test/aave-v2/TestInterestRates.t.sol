// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/aave-v2/InterestRatesManager.sol";
import "@forge-std/Test.sol";

contract TestInterestRates is InterestRatesManager, Test {
    using PercentageMath for uint256;
    using WadRayMath for uint256;

    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant RAY = 1e27;

    uint256 public p2pSupplyIndexTest = 1 * RAY;
    uint256 public p2pBorrowIndexTest = 1 * RAY;
    uint256 public poolSupplyIndexTest = 2 * RAY;
    uint256 public poolBorrowIndexTest = 3 * RAY;
    Types.PoolIndexes public lastPoolIndexesTest =
        Types.PoolIndexes(uint32(block.timestamp), uint112(1 * RAY), uint112(1 * RAY));
    uint256 public reserveFactor0PerCentTest = 0;
    uint256 public reserveFactor50PerCentTest = 5_000;
    uint256 public p2pIndexCursorTest = 3_333;

    // prettier-ignore
    function computeP2PIndexes(InterestRatesManager.Params memory _params)
        public
        pure
        returns (uint256 p2pSupplyIndex_, uint256 p2pBorrowIndex_)
    {
        uint256 poolSupplyGrowthFactor = _params.poolSupplyIndex.rayDiv(_params.lastPoolIndexes.poolSupplyIndex);
        uint256 poolBorrowGrowthFactor = _params.poolBorrowIndex.rayDiv(_params.lastPoolIndexes.poolBorrowIndex);
        uint256 p2pGrowthFactor = (poolSupplyGrowthFactor.percentMul(PercentageMath.PERCENTAGE_FACTOR - _params.p2pIndexCursor) + poolBorrowGrowthFactor.percentMul(_params.p2pIndexCursor));
        uint256 shareOfTheSupplyDelta = _params.delta.p2pBorrowAmount > 0
            ? (_params.delta.p2pSupplyDelta.rayMul(_params.lastPoolIndexes.poolSupplyIndex)).rayDiv(
                _params.delta.p2pSupplyAmount.rayMul(_params.lastP2PSupplyIndex))
            : 0;
        uint256 shareOfTheBorrowDelta = _params.delta.p2pSupplyAmount > 0
            ? (_params.delta.p2pBorrowDelta.rayMul(_params.lastPoolIndexes.poolBorrowIndex)).rayDiv(
                _params.delta.p2pBorrowAmount.rayMul(_params.lastP2PBorrowIndex))
            : 0;
        if (poolSupplyGrowthFactor <= poolBorrowGrowthFactor) {
            uint256 p2pSupplyGrowthFactor = p2pGrowthFactor - _params.reserveFactor.percentMul(p2pGrowthFactor - poolSupplyGrowthFactor);
            uint256 p2pBorrowGrowthFactor = p2pGrowthFactor + _params.reserveFactor.percentMul(poolBorrowGrowthFactor - p2pGrowthFactor);
            p2pSupplyIndex_ =
                _params.lastP2PSupplyIndex.rayMul(
                    (RAY - shareOfTheSupplyDelta).rayMul(p2pSupplyGrowthFactor) +
                    shareOfTheSupplyDelta.rayMul(poolSupplyGrowthFactor)
                );
            p2pBorrowIndex_ =
                _params.lastP2PBorrowIndex.rayMul(
                    (RAY - shareOfTheBorrowDelta).rayMul(p2pBorrowGrowthFactor) +
                    shareOfTheBorrowDelta.rayMul(poolBorrowGrowthFactor)
                );
        } else {
            p2pSupplyIndex_ =
                _params.lastP2PSupplyIndex.rayMul(
                    (RAY - shareOfTheSupplyDelta).rayMul(poolBorrowGrowthFactor) + 
                    shareOfTheSupplyDelta.rayMul(poolSupplyGrowthFactor)
                );
            p2pBorrowIndex_ = 
                _params.lastP2PBorrowIndex.rayMul(poolBorrowGrowthFactor); 
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
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
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
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
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
            Types.Delta(1 * RAY, 1 * RAY, 4 * RAY, 6 * RAY)
        );

        (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = _computeP2PIndexes(params); // prettier-ignore
        (uint256 expectedNewP2PSupplyIndex, uint256 expectedNewP2PBorrowIndex) = computeP2PIndexes(params); // prettier-ignore
        assertApproxEqAbs(newP2PSupplyIndex, expectedNewP2PSupplyIndex, 1);
        assertApproxEqAbs(newP2PBorrowIndex, expectedNewP2PBorrowIndex, 1);
    }
}
